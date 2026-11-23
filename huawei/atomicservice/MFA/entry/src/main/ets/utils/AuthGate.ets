// 自动跳转登录页的节流器。
//
// 背景：任意请求返回「token 失效」都会经 http 拦截器自动跳登录页。当后端响应在超时边界抖动、
// 或刷新后仍被判失效时，会出现「登录页 → 首页 → 登录页」的反复跳转。这里做三件事：
// 1) 单飞 + 去抖：同一次跳转只 push 一次，1s 内的重复信号直接丢弃；
// 2) 时间窗上限：60s 内最多自动跳 3 次，超出只记日志（避免服务端持续判失效时的死循环）；
// 3) 登录成功后 reset()：正常的下一次失效不应被上一次的跳转次数牵连。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';

const DEBOUNCE_MS: number = 1000;
const WINDOW_MS: number = 60000;
const LIMIT: number = 3;

export class AuthGate {
  private static _redirecting: boolean = false;
  private static _lastAt: number = 0;
  private static _windowAt: number = 0;
  private static _count: number = 0;

  // 是否允许本次自动跳转；返回 true 后调用方必须在延迟 push 结束时调用 finish()
  static allow(now: number): boolean {
    if (AuthGate._redirecting) {
      return false;
    }

    if (AuthGate._lastAt > 0 && now - AuthGate._lastAt < DEBOUNCE_MS) {
      return false;
    }

    if (0 === AuthGate._windowAt || now - AuthGate._windowAt > WINDOW_MS) {
      AuthGate._windowAt = now;
      AuthGate._count = 0;
    }

    if (AuthGate._count >= LIMIT) {
      hilog.warn(LogDomain.UTILS, 'utils/auth_gate', '60s 内自动跳转登录页已达上限，忽略本次: count=%{public}d',
        AuthGate._count);

      return false;
    }

    AuthGate._count++;
    AuthGate._lastAt = now;
    AuthGate._redirecting = true;

    return true;
  }

  // 延迟 push 结束（无论是否真的入栈）：必须复位单飞标记，否则后续跳转全部被挡
  static finish(): void {
    AuthGate._redirecting = false;
  }

  // 登录成功：只清掉单飞与去抖标记，**不重置 60s 计数**。
  // 若在每次登录成功后清零计数，遇到「登录成功但后续请求仍判失效」的异常场景会形成无限跳转；
  // 正常使用中 60s 窗口会自然过期（每次 token 失效间隔远大于 60s）。
  static reset(): void {
    AuthGate._redirecting = false;
    AuthGate._lastAt = 0;
  }
}
