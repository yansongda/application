// TOTP 时间窗的纯计算（无 ArkUI / 网络 / preferences 依赖，可在 `entry/src/test` 单测）。
//
// 与 `@yansongda/otp` 的 TOTP 内部完全一致：step = floor(ts_ms / 1000 / period)，
// remaining = period - floor(ts_ms / 1000) % period ∈ [1, period]。
// 唯一定义在这里，倒计时与「验证码翻转」用同一个函数，杜绝两套算法各自演化后错开。
//
// 不变量：period 必须是**正整数秒**（由 `utils/TotpParams.ets#normalizePeriod` 保证），
// 亚秒周期不在此支持范围内（统一 ticker 的粒度就是 1s）。
export interface TotpWindow {
  // 当前时间窗序号：变化即「该换验证码了」
  step: number;
  // 当前窗口剩余整秒 ∈ [1, period]
  remaining: number;
  // 窗口进度 [0, 1)：供环形 / 线性进度条
  ratio: number;
}

export function stepOf(nowMs: number, period: number): number {
  return Math.floor(Math.floor(nowMs / 1000) / period);
}

export function remainingOf(nowMs: number, period: number): number {
  return period - (Math.floor(nowMs / 1000) % period);
}

export function windowOf(nowMs: number, period: number): TotpWindow {
  const remaining: number = remainingOf(nowMs, period);

  return {
    step: stepOf(nowMs, period),
    remaining: remaining,
    ratio: (period - remaining) / period,
  };
}
