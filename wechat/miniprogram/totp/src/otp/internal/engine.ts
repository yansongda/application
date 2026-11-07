/**
 * 编排层：counter → code 全链路（纯函数，接收注入 provider，无平台依赖）。
 * 取模只在 digits.format 做一次；verify 扫完全部候选后才返回首个命中 delta（恒定时间）。
 */
import { OtpError, OtpErrorCode } from "../errors";
import type { OtpAlgorithm } from "../options";
import { isSafeCounter, toBytes } from "./counter";
import type { HmacProvider } from "./crypto-provider";
import { format as formatDigits } from "./digits";
import { constantTimeEquals } from "./time-step";
import { apply as truncateApply } from "./truncate";

export interface EngineParams {
  algorithm: OtpAlgorithm;
  digits: number;
  key: Uint8Array;
}

export function generate(
  provider: HmacProvider,
  params: EngineParams,
  counter: number,
): string {
  const digest = provider.sign(params.algorithm, params.key, toBytes(counter));
  return formatDigits(truncateApply(digest), params.digits);
}

/** token 必须为纯数字且非空；逐字符校验，避免正则。 */
function isNumericToken(token: string): boolean {
  if (token.length === 0) {
    return false;
  }
  for (let i = 0; i < token.length; i++) {
    const c = token.charCodeAt(i);
    if (c < 48 || c > 57) {
      return false;
    }
  }
  return true;
}

export function verify(
  provider: HmacProvider,
  params: EngineParams,
  token: string,
  counter: number,
  window: number,
): number | null {
  if (!isNumericToken(token) || token.length !== params.digits) {
    throw new OtpError(OtpErrorCode.INVALID_TOKEN, "INVALID_TOKEN");
  }
  if (!isSafeCounter(counter)) {
    throw new OtpError(OtpErrorCode.INVALID_COUNTER, "INVALID_COUNTER");
  }
  if (!Number.isInteger(window) || window < 0) {
    throw new OtpError(OtpErrorCode.INVALID_WINDOW, "INVALID_WINDOW");
  }

  let firstMatch: number | null = null;
  for (let delta = -window; delta <= window; delta++) {
    const candidate = counter + delta;
    if (candidate < 0 || !isSafeCounter(candidate)) {
      continue;
    }
    const candidateToken = generate(provider, params, candidate);
    if (constantTimeEquals(candidateToken, token)) {
      if (firstMatch === null) {
        // window=0 时循环首项是 -0：归一化为 +0，避免调用方用 Object.is 判断时出现意外
        firstMatch = delta === 0 ? 0 : delta;
      }
    }
  }
  return firstMatch;
}
