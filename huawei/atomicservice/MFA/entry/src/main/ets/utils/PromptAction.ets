// 弹窗窗口层：只负责「开 / 关 / 等退场」，不掺业务语义。
//
// 三个子职责：
// - `Dialog`：窗口原语 + awaitable close（`onDidDisappear` 回调 + 兜底超时）
// - `Busy`：全局单飞 loading（引用计数 + 打开代号 + 看门狗）
// - `Alert`：单槽位重试 / 失败框（串行化 + 打开代号）
//
// 页面统一使用 `Dialog.openLoading / closeLoading / openAlert / execute`；
// 不要再直接 `Dialog.open` 承载 loading（会新开窗口，两个 loading 同屏）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';
import { AppStorageV2, UIContext } from '@kit.ArkUI';
import { PromptAction as OhosPromptAction } from '@ohos.arkui.UIContext';
import promptAction from '@ohos.promptAction';
import { AuthExpiredError } from './Errors';
import { loginInStack } from './NavState';

// 关闭兜底：正常情况下 `onDidDisappear` 会立即回调；系统异常 / 回调缺失时最多等这么久
const CLOSE_FALLBACK_MS: number = 500;
// loading 看门狗：任何异常分支漏关时兜底，避免 autoCancel:false 的遮罩永久挡住页面。
// 必须大于最长请求超时（备份接口 15s），否则会误杀进行中的请求。
const LOADING_WATCHDOG_MS: number = 45000;

interface ClosedToken {
  id: number | undefined;
  closed: boolean;
  waiters: Array<() => void>;
}

class PromptAction {
  private static _action: OhosPromptAction | undefined;

  protected static get action(): OhosPromptAction {
    if ('undefined' === typeof PromptAction._action) {
      PromptAction._action = AppStorageV2.connect(UIContext)!.getPromptAction();
    }

    return PromptAction._action;
  }
}

export class Dialog extends PromptAction {
  // 每个窗口的「已退场」令牌：`closeCustomDialog(id)` 是同步 void，无法 await，
  // 改用打开时注册的 `onDidDisappear` 回调 + 兜底超时，替代固定 200ms 猜测。
  private static _tokens: Map<number, ClosedToken> = new Map();

  static async open(builder: CustomBuilder): Promise<number | undefined> {
    const token: ClosedToken = { id: undefined, closed: false, waiters: [] };
    const onDidDisappear = (): void => {
      token.closed = true;

      // 令牌**不在**这里删：`AlertDialogV2` 点按钮后框架会自动关框，此时槽位（`Busy._id` / `Alert._id`）
      // 仍指向该 id。保留 closed 标记，下一次 `closeAndWait` / `waitClosed` 才能立刻判定「已退场」；
      // 若在这里删掉，它会退化成 500ms 兜底 + 对一个已不存在的 id 再调一次 `closeCustomDialog`（多一条错误日志）。
      // 条目数上界就是「当前 loading + 当前 alert + 上一个自关闭的 alert」，不会无限增长。
      const waiters: Array<() => void> = token.waiters;

      token.waiters = [];
      waiters.forEach((waiter: () => void): void => waiter());
    };

    try {
      const id: number | undefined = await PromptAction.action.openCustomDialog({
        builder,
        autoCancel: false,
        onDidDisappear: onDidDisappear,
      });

      if ('undefined' !== typeof id) {
        token.id = id;
        Dialog._tokens.set(id, token);
      }

      return id;
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/dialog', '调用 `openCustomDialog` 失败，调用链路: %{public}s',
        JSON.stringify(e));
    }

    return undefined;
  }

  static close(dialogId: number | undefined): void {
    if ('undefined' === typeof dialogId) {
      return;
    }

    try {
      PromptAction.action.closeCustomDialog(dialogId);
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/dialog', '调用 `closeCustomDialog` 失败，调用链路: %{public}s',
        JSON.stringify(e));
    }
  }

  // 关窗并等待真实退场（onDidDisappear）；拿不到令牌时按兜底超时返回
  static async closeAndWait(dialogId: number | undefined): Promise<void> {
    if ('undefined' === typeof dialogId) {
      return;
    }

    const token: ClosedToken | undefined = Dialog._tokens.get(dialogId);

    // 窗口已自行退场（用户点了 alert 按钮 / 被系统取消）：不用再关，也不用等兜底
    if ('undefined' !== typeof token && token.closed) {
      Dialog._tokens.delete(dialogId);

      return;
    }

    Dialog.close(dialogId);

    await Dialog.waitClosed(dialogId);
  }

  // 等指定窗口退场（不主动关闭）；拿不到令牌（窗口已清理或从未登记）时按兜底超时返回
  static async waitClosed(dialogId: number | undefined): Promise<void> {
    if ('undefined' === typeof dialogId) {
      return;
    }

    const token: ClosedToken | undefined = Dialog._tokens.get(dialogId);

    if ('undefined' === typeof token) {
      // 令牌缺失：窗口可能在登记前就被清场。作为「令牌表清理逻辑漏了」的探针，日志里留一条 warn。
      hilog.warn(LogDomain.UTILS, 'utils/dialog', '等待窗口退场时找不到令牌，按兜底超时返回: id=%{public}d', dialogId);

      await Dialog.fallback();
      return;
    }

    if (token.closed) {
      Dialog._tokens.delete(dialogId);
      return;
    }

    await new Promise<void>((resolve: () => void): void => {
      const timer: number = setTimeout(() => {
        resolve();
      }, CLOSE_FALLBACK_MS);

      token.waiters.push(() => {
        clearTimeout(timer);
        resolve();
      });
    });

    Dialog._tokens.delete(dialogId);
  }

  // --- 对页面的稳定门面（与 Busy/Alert 组合） ---

  static async openLoading(builder: CustomBuilder): Promise<number | undefined> {
    return Busy.open(builder);
  }

  static async closeLoading(): Promise<void> {
    await Busy.close();
  }

  static async openAlert(builder: CustomBuilder): Promise<number | undefined> {
    return Alert.open(builder);
  }

  // 强制清场并等待全部退场（跳登录页 / 打开重试框前使用）
  static async closeAllAsync(): Promise<void> {
    const loadingId: number | undefined = Busy.reset();
    const alertId: number | undefined = Alert.reset();

    await Dialog.closeAndWait(loadingId);
    await Dialog.closeAndWait(alertId);
  }

  static async execute<T>(openBuilder: CustomBuilder, callback: () => Promise<T>,
    retryBuilder?: CustomBuilder): Promise<T> {
    await Busy.open(openBuilder);

    let error: undefined | Error = undefined;

    try {
      const result = await callback();

      await Busy.close();

      return result;
    } catch (e) {
      error = e;
    }

    await Busy.close();

    // 认证失效已由 SessionGuard 跳转登录页：再弹重试框只会叠在登录页上方
    if ('undefined' !== typeof retryBuilder && !(error instanceof AuthExpiredError)) {
      await Alert.open(retryBuilder);
    }

    return Promise.reject(error);
  }

  private static async fallback(): Promise<void> {
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(() => {
        resolve();
      }, CLOSE_FALLBACK_MS);
    });
  }
}

// 全局单飞 loading：同一时刻最多一个窗口，引用计数归零才真正关闭。
export class Busy {
  private static _id: number | undefined = undefined;
  private static _refs: number = 0;
  private static _opening: Promise<number | undefined> | undefined = undefined;
  private static _timer: number | undefined = undefined;
  // 打开代号：`reset()` 自增。打开中的窗口如果跨越了清场，会因代号不匹配而自关，避免孤儿窗口
  private static _gen: number = 0;

  static async open(builder: CustomBuilder): Promise<number | undefined> {
    Busy._refs++;

    if ('undefined' !== typeof Busy._id) {
      return Busy._id;
    }

    if ('undefined' !== typeof Busy._opening) {
      return Busy._opening;
    }

    const gen: number = Busy._gen;
    const opening: Promise<number | undefined> = (async (): Promise<number | undefined> => {
      // 重试框按钮的同步 action 会立刻调用 open：先关掉上一个 alert 并等它真正退场，避免两个窗口同屏。
      // 这一步取代了各页面各自 setTimeout(200) 的写法。
      await Alert.dismissAndWait();

      // 等待期间可能发生清场（跳登录页）或调用方已全部释放：此时不要再开窗，
      // 否则窗口会先真的显示出来、再因代号不匹配被关掉，表现为「登录页上闪一下 loading」。
      if (gen !== Busy._gen || Busy._refs <= 0) {
        return undefined;
      }

      const id: number | undefined = await Dialog.open(builder);

      if ('undefined' === typeof id) {
        return undefined;
      }

      if (gen !== Busy._gen) {
        await Dialog.closeAndWait(id);

        return undefined;
      }

      // 打开期间调用方已经全部释放（请求秒回）：立即关掉，不要把窗口留到看门狗
      if (Busy._refs <= 0) {
        await Dialog.closeAndWait(id);

        return undefined;
      }

      Busy._id = id;
      Busy.watch(id);

      return id;
    })();

    Busy._opening = opening;

    try {
      return await opening;
    } finally {
      if (Busy._opening === opening) {
        Busy._opening = undefined;
      }
    }
  }

  static async close(): Promise<void> {
    Busy._refs = Busy._refs > 0 ? Busy._refs - 1 : 0;

    if (Busy._refs > 0) {
      return;
    }

    if ('undefined' !== typeof Busy._opening) {
      try {
        await Busy._opening;
      } catch (e) {
        // 打开失败：没有窗口可关
      }
    }

    const id: number | undefined = Busy._id;

    Busy.clearWatchdog();
    Busy._id = undefined;

    if ('undefined' === typeof id) {
      return;
    }

    await Dialog.closeAndWait(id);
  }

  // 强制清场：自增代号、清空计数与看门狗，返回待关闭的窗口 id
  static reset(): number | undefined {
    Busy._gen++;

    const id: number | undefined = Busy._id;

    Busy._id = undefined;
    Busy._refs = 0;
    Busy._opening = undefined;
    Busy.clearWatchdog();

    return id;
  }

  private static watch(id: number): void {
    Busy.clearWatchdog();

    Busy._timer = setTimeout(() => {
      Busy._timer = undefined;

      if (Busy._id !== id) {
        return;
      }

      hilog.error(LogDomain.UTILS, 'utils/dialog', 'loading 超时未关闭，强制关闭: id=%{public}d', id);

      Busy._id = undefined;
      Busy._refs = 0;
      Dialog.close(id);
    }, LOADING_WATCHDOG_MS);
  }

  private static clearWatchdog(): void {
    if ('undefined' === typeof Busy._timer) {
      return;
    }

    clearTimeout(Busy._timer);
    Busy._timer = undefined;
  }
}

// 重试 / 失败框：同一时刻最多一个，并发打开请求串行化
export class Alert {
  private static _id: number | undefined = undefined;
  private static _opening: Promise<number | undefined> | undefined = undefined;
  private static _gen: number = 0;

  static async open(builder: CustomBuilder): Promise<number | undefined> {
    if ('undefined' !== typeof Alert._opening) {
      try {
        await Alert._opening;
      } catch (e) {
        // 上一个 alert 打开失败：继续打开当前这个
      }
    }

    const gen: number = Alert._gen;
    const opening: Promise<number | undefined> = (async (): Promise<number | undefined> => {
      const previous: number | undefined = Alert._id;

      Alert._id = undefined;

      if ('undefined' !== typeof previous) {
        // 等旧框真正退场，避免新旧两个 alert 同屏
        await Dialog.closeAndWait(previous);
      }

      // 等旧框期间可能发生了清场：不要再开新窗（同 Busy.open 的说明）
      if (gen !== Alert._gen) {
        return undefined;
      }

      const id: number | undefined = await Dialog.open(builder);

      if ('undefined' === typeof id) {
        return undefined;
      }

      if (gen !== Alert._gen) {
        await Dialog.closeAndWait(id);

        return undefined;
      }

      Alert._id = id;

      return id;
    })();

    Alert._opening = opening;

    try {
      return await opening;
    } finally {
      if (Alert._opening === opening) {
        Alert._opening = undefined;
      }
    }
  }

  static reset(): number | undefined {
    Alert._gen++;

    const id: number | undefined = Alert._id;

    Alert._id = undefined;

    return id;
  }

  // 打开 loading 前调用：关掉当前 alert 并等它真正退场，替代页面里的 setTimeout 延迟。
  // 必须**主动关闭**而不是只等待：alert 可能仍在等用户操作（此时它并没有在退场），只等待会让槽位
  // 提前清空、窗口却留在屏幕上，`closeAllAsync()` 之后也再关不掉它（孤儿窗口）。
  // 用「读并清空槽位」而不是 `reset()`：`reset()` 会自增代号，把正在打开中的重试框一并取消掉。
  static async dismissAndWait(): Promise<void> {
    const id: number | undefined = Alert._id;

    Alert._id = undefined;

    if ('undefined' === typeof id) {
      return;
    }

    await Dialog.closeAndWait(id);
  }
}

export class Toast extends PromptAction {
  static show(options: promptAction.ShowToastOptions): void {
    // 登录页在前台时业务提示一律静默（避免登录 loading 之上再叠 toast）；
    // 用 includes 而非 [0]：登录页可能压在下层页面之上，不在栈底
    if (loginInStack()) {
      return;
    }

    try {
      PromptAction.action.showToast(options);
    } catch (error) {
      hilog.warn(LogDomain.UTILS, 'utils/toast', '调用 `showToast` 失败: %{public}s', JSON.stringify(error));
    }
  }

  static async execute<T>(
    callback: () => Promise<T>,
    openBuilder?: CustomBuilder,
    successMessage?: Resource | string | undefined,
    failedMessage?: Resource | string | undefined
  ): Promise<T> {
    let withDialog: boolean = false;

    if ('undefined' !== typeof openBuilder) {
      withDialog = true;

      await Busy.open(openBuilder);
    }

    try {
      const result = await callback();

      if (withDialog) {
        await Busy.close();
      }

      if (successMessage) {
        Toast.show({
          message: successMessage,
          duration: 3000,
        });
      }

      return result;
    } catch (e) {
      if (withDialog) {
        await Busy.close();
      }

      // 认证失效已由登录页接管：不要再弹失败 toast
      if (!(e instanceof AuthExpiredError)) {
        Toast.show({
          message: failedMessage ?? e.message,
          duration: 3000,
        });
      }

      return Promise.reject(e);
    }
  }
}
