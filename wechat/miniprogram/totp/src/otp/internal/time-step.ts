/**
 * 时间步 / 剩余秒 / 进度 / 恒定时间比较（纯函数，无平台依赖）。
 * 只做纯数值运算，不依赖 Date / 时区；t0 单位秒。
 */
import { OtpError, OtpErrorCode } from "../errors";

/** 校验公共入参：epochMs > 0 有限数、t0 ≥ 0 整数、period 正整数。 */
function assertValidInputs(epochMs: number, t0: number, period: number): void {
  if (!Number.isFinite(epochMs) || epochMs <= 0) {
    throw new OtpError(OtpErrorCode.INVALID_TIMESTAMP, "INVALID_TIMESTAMP");
  }
  if (!Number.isInteger(t0) || t0 < 0) {
    throw new OtpError(OtpErrorCode.INVALID_T0, "INVALID_T0");
  }
  if (!Number.isInteger(period) || period <= 0) {
    throw new OtpError(OtpErrorCode.INVALID_PERIOD, "INVALID_PERIOD");
  }
}

/** RFC 6238 §4.2：counter = floor((floor(epochMs/1000) - t0) / period)。 */
export function step(epochMs: number, t0: number, period: number): number {
  assertValidInputs(epochMs, t0, period);
  return Math.floor((Math.floor(epochMs / 1000) - t0) / period);
}

/** 距本时间步结束的剩余秒数 [1, period]；按 epoch 秒取模（含 t0 偏移与负值归一化），不依赖本地时区。 */
export function remainingSec(
  epochMs: number,
  t0: number,
  period: number,
): number {
  assertValidInputs(epochMs, t0, period);
  const s = Math.floor(epochMs / 1000);
  return period - ((((s - t0) % period) + period) % period);
}

/** 本时间步内已走过的比例 [0, 1)。 */
export function progress(epochMs: number, t0: number, period: number): number {
  assertValidInputs(epochMs, t0, period);
  const s = Math.floor(epochMs / 1000);
  return ((((s - t0) % period) + period) % period) / period;
}

/** 恒定时间比较：逐字符异或累加；仅长度不等时提前返回 false，其余路径不早退。 */
export function constantTimeEquals(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
