import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPagesName, LogDomain } from '../App';
import { AppStorageV2, UIContext } from '@kit.ArkUI';
import { PromptAction as OhosPromptAction } from '@ohos.arkui.UIContext';
import promptAction from '@ohos.promptAction';
import { AuthExpiredError } from './Errors';

// 关闭弹窗后给退场动画留的间隙：`closeCustomDialog(dialogId)` 只有同步 void 形态（SDK 定义），
// 但它内部要等窗口退场；紧接着调用 `openCustomDialog` 会出现两个弹窗短暂同屏。
const CLOSE_GAP_MS: number = 200;
// loading 看门狗：任何异常分支漏关时兜底，避免 autoCancel:false 的遮罩永久挡住页面。
// 必须大于最长请求超时（备份接口 15s），否则会误杀进行中的请求。
const LOADING_WATCHDOG_MS: number = 45000;

class PromptAction {
  private static _action: OhosPromptAction | undefined;

  protected static get action(): OhosPromptAction {
    if ('undefined' === typeof PromptAction._action) {
      PromptAction._action = AppStorageV2.connect(UIContext)!.getPromptAction();
    }

    return PromptAction._action;
  }

  private static _pages: NavPathStack | undefined;

  protected static get pages(): NavPathStack {
    if ('undefined' === typeof PromptAction._pages) {
      PromptAction._pages = AppStorageV2.connect(NavPathStack)!;
    }

    return PromptAction._pages;
  }
}

export class Dialog extends PromptAction {
  // 全局单飞 loading：同一时刻最多一个 loading 窗口。多个页面并发打开时复用同一个 id，
  // 靠引用计数决定真正关闭的时机（登录页 / 首页刷新 / 业务提交都可能同时要求 loading）。
  private static _loadingId: number | undefined = undefined;
  private static _loadingRefs: number = 0;
  private static _loadingOpening: Promise<number | undefined> | undefined = undefined;
  private static _loadingTimer: number | undefined = undefined;

  // 重试 / 失败框也单槽位：新框打开前先关旧框，避免叠加
  private static _alertId: number | undefined = undefined;
  private static _alertOpening: Promise<number | undefined> | undefined = undefined;

  // 代号：`closeAll()` 自增。打开中的窗口如果跨越了 `closeAll`，其 promise 回调会因代号不匹配
  // 而把自己关掉，避免「强制清场后旧窗口复活 / 泄漏成无引用窗口」。
  private static _loadingGen: number = 0;
  private static _alertGen: number = 0;

  static async open(builder: CustomBuilder): Promise<number | undefined> {
    try {
      return await PromptAction.action.openCustomDialog({ builder, autoCancel: false });
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/dialog', '调用 `openCustomDialog` 失败，调用链路: %{public}s',
        JSON.stringify(e));
    }

    return undefined;
  }

  static close(dialogId: number | undefined) {
    if ('undefined' === typeof dialogId) {
      return;
    }

    if (Dialog._loadingId === dialogId) {
      Dialog._loadingId = undefined;
    }

    if (Dialog._alertId === dialogId) {
      Dialog._alertId = undefined;
    }

    try {
      PromptAction.action.closeCustomDialog(dialogId);
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/dialog', '调用 `closeCustomDialog` 失败，调用链路: %{public}s',
        JSON.stringify(e));
    }
  }

  // 打开 loading（全局单飞）：已有 loading 时复用窗口，只增加引用计数
  static async openLoading(builder: CustomBuilder): Promise<number | undefined> {
    Dialog._loadingRefs++;

    if ('undefined' !== typeof Dialog._loadingId) {
      return Dialog._loadingId;
    }

    if ('undefined' !== typeof Dialog._loadingOpening) {
      return Dialog._loadingOpening;
    }

    const gen: number = Dialog._loadingGen;
    const opening: Promise<number | undefined> = Dialog.open(builder)
      .then(async (id: number | undefined): Promise<number | undefined> => {
        // 只清理自己：`closeAll()` 之后可能已经开始了新一轮打开，不能把新 promise 置空
        if (Dialog._loadingOpening === opening) {
          Dialog._loadingOpening = undefined;
        }

        if ('undefined' === typeof id) {
          return undefined;
        }

        // 打开期间发生过强制清场：本窗口已不属于当前一轮，直接关掉
        if (gen !== Dialog._loadingGen) {
          Dialog.close(id);

          return undefined;
        }

        // 打开期间调用方已经全部释放（请求秒回）：立即关掉，不要把窗口留到看门狗
        if (Dialog._loadingRefs <= 0) {
          Dialog.close(id);

          return undefined;
        }

        Dialog._loadingId = id;
        Dialog.watch(id);

        return id;
      });

    Dialog._loadingOpening = opening;

    return opening;
  }

  // 释放一次引用；归零才真正关闭，并等待退场间隙
  static async closeLoading(): Promise<void> {
    Dialog._loadingRefs = Dialog._loadingRefs > 0 ? Dialog._loadingRefs - 1 : 0;

    if (Dialog._loadingRefs > 0) {
      return;
    }

    if ('undefined' !== typeof Dialog._loadingOpening) {
      await Dialog._loadingOpening;
    }

    const id: number | undefined = Dialog._loadingId;

    Dialog.clearWatchdog();
    Dialog._loadingId = undefined;

    if ('undefined' === typeof id) {
      return;
    }

    Dialog.close(id);

    await Dialog.settle();
  }

  // 打开重试 / 失败框（单槽位）：并发调用排队，先关旧框再开新框，避免叠加
  static async openAlert(builder: CustomBuilder): Promise<number | undefined> {
    if ('undefined' !== typeof Dialog._alertOpening) {
      try {
        await Dialog._alertOpening;
      } catch (e) {
        // 上一个 alert 打开失败：继续打开当前这个
      }
    }

    const gen: number = Dialog._alertGen;
    const opening: Promise<number | undefined> = (async (): Promise<number | undefined> => {
      if ('undefined' !== typeof Dialog._alertId) {
        Dialog.close(Dialog._alertId);
        Dialog._alertId = undefined;

        await Dialog.settle();
      }

      const id: number | undefined = await Dialog.open(builder);

      // 打开期间发生过强制清场：直接关掉，避免幽灵窗口
      if (gen !== Dialog._alertGen) {
        Dialog.close(id);

        return undefined;
      }

      Dialog._alertId = id;

      return id;
    })();

    Dialog._alertOpening = opening;

    try {
      return await opening;
    } finally {
      if (Dialog._alertOpening === opening) {
        Dialog._alertOpening = undefined;
      }
    }
  }

  // 强制清场（跳登录页前）：把 loading 与重试框全部关掉，避免「首页弹窗 + 登录页 loading」同屏
  static closeAll(): void {
    Dialog._loadingGen++;
    Dialog._alertGen++;

    const loadingId: number | undefined = Dialog._loadingId;
    const alertId: number | undefined = Dialog._alertId;

    Dialog._loadingId = undefined;
    Dialog._alertId = undefined;
    Dialog._loadingRefs = 0;
    Dialog._loadingOpening = undefined;
    Dialog.clearWatchdog();

    Dialog.close(loadingId);
    Dialog.close(alertId);
  }

  static async execute<T>(openBuilder: CustomBuilder, callback: () => Promise<T>,
    retryBuilder?: CustomBuilder): Promise<T> {
    await Dialog.openLoading(openBuilder);

    let error: undefined | Error = undefined;

    try {
      const result = await callback();

      // 关 loading 会等退场间隙；这样失败分支打开重试框时不会与 loading 同屏
      await Dialog.closeLoading();

      return result;
    } catch (e) {
      error = e;
    }

    await Dialog.closeLoading();

    // 认证失效已由 Http 拦截器跳转登录页：再弹重试框只会叠在登录页上方，交由登录页处理
    if ('undefined' !== typeof retryBuilder && !(error instanceof AuthExpiredError)) {
      await Dialog.openAlert(retryBuilder);
    }

    return Promise.reject(error);
  }

  // 等弹窗退场：closeCustomDialog 没有 Promise 形态，只能按固定间隙让位
  static async settle(): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, CLOSE_GAP_MS);
    });
  }

  private static watch(id: number): void {
    Dialog.clearWatchdog();

    Dialog._loadingTimer = setTimeout(() => {
      Dialog._loadingTimer = undefined;

      if (Dialog._loadingId !== id) {
        return;
      }

      hilog.error(LogDomain.UTILS, 'utils/dialog', 'loading 超时未关闭，强制关闭: id=%{public}d', id);

      Dialog._loadingId = undefined;
      Dialog._loadingRefs = 0;
      Dialog.close(id);
    }, LOADING_WATCHDOG_MS);
  }

  private static clearWatchdog(): void {
    if ('undefined' === typeof Dialog._loadingTimer) {
      return;
    }

    clearTimeout(Dialog._loadingTimer);
    Dialog._loadingTimer = undefined;
  }
}

export class Toast extends PromptAction {
  static show(options: promptAction.ShowToastOptions): void {
    // 登录页在前台时业务提示一律静默（避免登录 loading 之上再叠 toast）；
    // 用 includes 而非 [0]：登录页可能压在下层页面之上，不在栈底
    if (PromptAction.pages.getAllPathName().includes(AppPagesName.LOGIN.toString())) {
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

      await Dialog.openLoading(openBuilder);
    }

    try {
      const result = await callback();

      if (withDialog) {
        await Dialog.closeLoading();
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
        await Dialog.closeLoading();
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
