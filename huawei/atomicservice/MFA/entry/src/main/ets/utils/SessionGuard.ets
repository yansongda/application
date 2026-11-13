// 认证事件 → 导航策略的唯一入口。
//
// Http 层只负责「发现认证失效」并通过 `configureHttp({ authExpired })` 回调通知；
// 本模块决定是否跳、跳几次、何时跳：
// 1) 登录页已在栈中：忽略；
// 2) `SessionThrottle`：1s 去抖 + 60s/3 次上限（防「登录页 ↔ 首页」来回跳）；
// 3) 跳转前 `Dialog.closeAllAsync()`：等 loading / 重试框真正退场（`onDidDisappear`）再入栈；
// 4) 延迟一个宏任务入栈，让请求 Promise reject 后的调用方 catch（记日志 / 清理）先跑完。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPagesName, LogDomain } from '../App';
import { LoginPageParams } from '../types/Login';
import { State } from '../types/Session';
import { Dialog } from './PromptAction';
import { loginInStack, navPages } from './NavState';
import { SessionThrottle } from './SessionThrottle';

const throttle: SessionThrottle = new SessionThrottle();

export class SessionGuard {
  // Http 拦截器回调：认证失效（token 缺失 / 过期 / 非法）
  static onAuthExpired(state: State): void {
    SessionGuard.redirect(state);
  }

  // 手动 / 自动跳转登录页的统一入口
  static redirect(state?: State): void {
    if (loginInStack()) {
      return;
    }

    if (!throttle.allow(Date.now())) {
      // 不提示、不再弹框：这类信号通常来自同一轮抖动的多个请求，提示只会叠在页面上
      hilog.warn(LogDomain.UTILS, 'utils/session_guard',
        '忽略本次自动跳转登录页（去抖中或 60s 内已达 %{public}d 次）', throttle.count);

      return;
    }

    SessionGuard.redirectAsync(state).catch((e: Error): void => {
      hilog.error(LogDomain.UTILS, 'utils/session_guard', '跳转登录页失败: %{public}s', JSON.stringify(e));
      throttle.finish();
    });
  }

  // 登录成功：复位去抖/单飞标记（不重置 60s 计数）
  static resetAfterLogin(): void {
    throttle.resetAfterLogin();
  }

  static isLoginVisible(): boolean {
    return loginInStack();
  }

  private static async redirectAsync(state?: State): Promise<void> {
    try {
      // 先清场并等到退场动画结束，避免「上个页面的弹窗 + 登录页 loading」同屏
      await Dialog.closeAllAsync();

      // 让出一个宏任务：调用方的失败清理（关 loading / 记日志）先跑完
      await SessionGuard.nextTask();

      if (loginInStack()) {
        return;
      }

      // 等待期间调用方可能又打开了失败框：入栈前再清一次
      await Dialog.closeAllAsync();

      const param: LoginPageParams | null =
        'undefined' === typeof state ? null : { forceAuthorizationState: state };

      navPages().pushPathByName(AppPagesName.LOGIN, param);
    } finally {
      throttle.finish();
    }
  }

  private static nextTask(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, 0);
    });
  }
}
