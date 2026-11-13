// 自动跳转登录页的节流器（纯逻辑，无 import，可单测）。
//
// 背景：任意请求返回「token 失效」都会自动跳登录页。当后端在超时边界抖动、
// 或刷新后仍被判失效时，会出现「登录页 → 首页 → 登录页」的反复跳转。这里做三件事：
// 1) 单飞 + 去抖：同一次跳转只放行一次，1s 内的重复信号直接丢弃；
// 2) 时间窗上限：60s 内最多自动跳 3 次，超出只记日志（避免服务端持续判失效时的死循环）；
// 3) 登录成功后 resetAfterLogin()：清掉单飞与去抖标记，不重置 60s 计数
//    （正常使用中窗口会自然过期；若清零，异常场景会重新形成无限跳转）。
export const DEBOUNCE_MS: number = 1000;
export const WINDOW_MS: number = 60000;
export const LIMIT: number = 3;

export class SessionThrottle {
  private _redirecting: boolean = false;
  private _lastAt: number = 0;
  private _windowAt: number = 0;
  private _count: number = 0;

  // 是否允许本次自动跳转；返回 true 后调用方必须在跳转结束时调用 finish()
  allow(now: number): boolean {
    if (this._redirecting) {
      return false;
    }

    if (this._lastAt > 0 && now - this._lastAt < DEBOUNCE_MS) {
      return false;
    }

    if (0 === this._windowAt || now - this._windowAt > WINDOW_MS) {
      this._windowAt = now;
      this._count = 0;
    }

    if (this._count >= LIMIT) {
      return false;
    }

    this._count++;
    this._lastAt = now;
    this._redirecting = true;

    return true;
  }

  // 跳转结束（无论是否真的入栈）：必须复位单飞标记，否则后续跳转全部被挡
  finish(): void {
    this._redirecting = false;
  }

  // 登录成功：只清掉单飞与去抖标记，60s 计数保留
  resetAfterLogin(): void {
    this._redirecting = false;
    this._lastAt = 0;
  }

  // 供日志/测试观察当前窗口内已自动跳转的次数
  get count(): number {
    return this._count;
  }
}
