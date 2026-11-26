// 弹窗门面：`Dialog` / `Toast` 是对页面的唯一入口。
//
// 分层：
// - 并发决策（单飞 / 引用计数 / 代号 / 等真实退场 / 打开超时 / 看门狗）全在
//   `utils/dialog/WindowCoordinator.ets`——纯逻辑，可在 `entry/src/test` 单测；
// - 本文件只做两件事：把 ArkUI 的 openCustomDialog / closeCustomDialog 与 setTimeout 注入进去，
//   以及给页面提供稳定门面。
//
// 页面使用约定：
// - loading 一律 `Dialog.openLoading(...)` 拿到租约并在 finally 里 `lease.release()`
//   （`Dialog.execute` / `Toast.execute` 内部已配对，手写流程才需要自己 release）；
// - 重试 / 失败框一律 `Dialog.openAlert(...)`；
// - 认证失效（AuthExpiredError）的跳转由 `SessionGuard` 负责，门面只会跳过重试框与失败 toast。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';
import { AppStorageV2, UIContext } from '@kit.ArkUI';
import { PromptAction as OhosPromptAction } from '@ohos.arkui.UIContext';
import promptAction from '@ohos.promptAction';
import { AuthExpiredError, errorMessage, toError } from './Errors';
import { loginInStack } from './NavState';
import {
  Clock,
  LoadingLease,
  WindowCoordinator,
  WindowLogger,
  WindowOpener,
  WindowTimings
} from './dialog/WindowCoordinator';

// 关窗兜底：正常情况下 `onDidDisappear` 会立即回调；系统异常 / 回调缺失时最多等这么久。
// （SDK 明确写了「退场动画被打断，例如同时触发弹窗关闭和页面切换」时该回调不触发，
//   `SessionGuard` 的「关框后立即 push」正好落在这个场景，属已知代价：不阻塞、不卡死。）
const CLOSE_FALLBACK_MS: number = 500;
// 打开兜底：`openCustomDialog` 一旦不 settle，窗口层的全局锁会永久卡住，之后整个 App 开不出弹窗
const OPEN_TIMEOUT_MS: number = 3000;
// loading 看门狗：任何异常分支漏关时兜底，避免 autoCancel:false 的遮罩永久挡住页面。
// 必须大于最长请求超时（备份接口 15s），否则会误杀进行中的请求。
const LOADING_WATCHDOG_MS: number = 45000;

const TIMINGS: WindowTimings = {
  closeFallbackMs: CLOSE_FALLBACK_MS,
  openTimeoutMs: OPEN_TIMEOUT_MS,
  loadingWatchdogMs: LOADING_WATCHDOG_MS,
};

class PromptAction {
  private static _action: OhosPromptAction | undefined;

  // 返回 undefined 表示 UIContext 尚未注册（早于 `EntryAbility.onWindowStageCreate` 的 loadContent 回调）。
  // 历史实现用 `context!`：那种场景下抛的是 TypeError，会打断调用方的业务分支且日志里看不出原因；
  // 现在改为「记日志 + 跳过本次弹窗」——弹窗缺失是可接受的降级，流程中断不是。
  static get action(): OhosPromptAction | undefined {
    if ('undefined' === typeof PromptAction._action) {
      const context: UIContext | undefined = AppStorageV2.connect(UIContext);

      if ('undefined' === typeof context) {
        hilog.error(LogDomain.UTILS, 'utils/prompt_action', 'UIContext 尚未注册，跳过本次弹窗');

        return undefined;
      }

      PromptAction._action = context.getPromptAction();
    }

    return PromptAction._action;
  }
}

class ArkClock implements Clock {
  after(delayMs: number, action: () => void): number {
    return setTimeout(action, delayMs);
  }

  cancel(handle: number): void {
    clearTimeout(handle);
  }
}

class ArkWindowLogger implements WindowLogger {
  warn(tag: string, message: string): void {
    hilog.warn(LogDomain.UTILS, tag, '%{public}s', message);
  }

  error(tag: string, message: string): void {
    hilog.error(LogDomain.UTILS, tag, '%{public}s', message);
  }
}

class ArkWindowOpener implements WindowOpener<CustomBuilder> {
  // `autoCancel: false`：loading / 重试框都不允许点遮罩关闭，否则会出现「窗口关了但流程还在跑」
  open(builder: CustomBuilder, onClosed: () => void): Promise<number | undefined> {
    const action: OhosPromptAction | undefined = PromptAction.action;

    if ('undefined' === typeof action) {
      // 没打开窗口就不会有 onDidDisappear：协调器按「打开失败」处理（窗口 id 为 undefined）
      return Promise.resolve(undefined);
    }

    return action.openCustomDialog({
      builder: builder,
      autoCancel: false,
      onDidDisappear: onClosed,
    });
  }

  close(windowId: number): void {
    const action: OhosPromptAction | undefined = PromptAction.action;

    if ('undefined' === typeof action) {
      return;
    }

    action.closeCustomDialog(windowId);
  }
}

const windows: WindowCoordinator<CustomBuilder> =
  new WindowCoordinator<CustomBuilder>(new ArkWindowOpener(), new ArkClock(), new ArkWindowLogger(), TIMINGS);

export class Dialog {
  // 打开（或复用）全局单飞 loading。
  // 返回的租约必须 `release()`：这决定了窗口什么时候真正关闭（引用归零），
  // 也决定了迟到的 release 不会误关下一轮窗口（租约带打开代号）。
  static openLoading(builder: CustomBuilder): Promise<LoadingLease> {
    return windows.openLoading(builder);
  }

  // 打开单槽位重试 / 失败框（并发调用会排队，先关旧框再开新框）
  static openAlert(builder: CustomBuilder): Promise<number | undefined> {
    return windows.openAlert(builder);
  }

  // 强制清场并等待全部退场（跳登录页前使用）
  static closeAllAsync(): Promise<void> {
    return windows.closeAll();
  }

  // 开 loading → 执行 → 关 loading（失败时按需弹重试框）
  static async execute<T>(openBuilder: CustomBuilder, callback: () => Promise<T>,
    retryBuilder?: CustomBuilder): Promise<T> {
    const lease: LoadingLease = await windows.openLoading(openBuilder);

    try {
      const result: T = await callback();

      await lease.release();

      return result;
    } catch (e) {
      // 先关 loading 并等它真正退场，再弹重试框：顺序反了两个窗口会同屏
      await lease.release();

      const error: Error = toError(e);

      // 认证失效已由 SessionGuard 跳转登录页：再弹重试框只会叠在登录页上方
      if ('undefined' !== typeof retryBuilder && !(error instanceof AuthExpiredError)) {
        await windows.openAlert(retryBuilder);
      }

      throw error;
    }
  }
}

export class Toast extends PromptAction {
  static show(options: promptAction.ShowToastOptions): void {
    // 登录页在前台时业务提示一律静默（避免登录 loading 之上再叠 toast）；
    // 用 includes 而非 [0]：登录页可能压在下层页面之上，不在栈底
    if (loginInStack()) {
      return;
    }

    const action: OhosPromptAction | undefined = PromptAction.action;

    if ('undefined' === typeof action) {
      return;
    }

    try {
      action.showToast(options);
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
    const lease: LoadingLease | undefined =
      'undefined' === typeof openBuilder ? undefined : await windows.openLoading(openBuilder);

    try {
      const result: T = await callback();

      if ('undefined' !== typeof lease) {
        await lease.release();
      }

      if (successMessage) {
        Toast.show({
          message: successMessage,
          duration: 3000,
        });
      }

      return result;
    } catch (e) {
      if ('undefined' !== typeof lease) {
        await lease.release();
      }

      const error: Error = toError(e);

      // 认证失效已由登录页接管：不要再弹失败 toast
      if (!(error instanceof AuthExpiredError)) {
        Toast.show({
          message: failedMessage ?? errorMessage(error),
          duration: 3000,
        });
      }

      throw error;
    }
  }
}
