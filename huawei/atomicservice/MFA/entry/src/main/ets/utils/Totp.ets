// TOTP **参数与时间窗**的唯一真相源（纯函数集合，无 ArkUI / 网络 / preferences 依赖，可在 `entry/src/test` 单测）。
//
// 注意：本文件是纯函数模块，与 `api/Totp.ets`（接口类 `Totp`）没有任何关系——同目录同名只是巧合。
//
// 一条不变量串起本文件全部内容：**period 必须是正整数秒**。
// - `normalizePeriod` / `normalizeDigits` / `normalizeAlgorithm` / `normalizeConfig` 负责**保证**它
//   （与后端 `Totp::period()/digits()/algorithm()` 的合法域一致，脏值一律回落默认值）；
// - `stepOf` / `remainingOf` 负责**消费**它（库内按 floor(ms/1000) % period 计算，period 为 0 时取模得
//   NaN，进度条会显示 0/0；period 为小数时 step 与倒计时都会变成非整数）。
// 二者必须同一处维护：拆成两个文件时「保证」与「依赖保证」分居两地，正是脏 period 能一路漏到 UI 的原因。
//
// 归一化只做一次（`normalizeConfig` → `NormConfig`）：下游**不得**再写 `?? 30` / `?? 6` /
// `typeof === 'number'` 之类兜底——历史实现里 `progress ?? 30`（列表）与 `progress ?? 0`（详情）并存，
// 同一份脏数据在两端表现不一致。
//
// `stepOf` / `remainingOf` 与 `@yansongda/otp` 的 `TOTP#remaining()` 逐点对齐（有用例锁定）：
// 倒计时与「验证码翻转」必须共用同一套取模，否则 period 非 60 约数（45s）或时区偏移非整小时（+05:30）
// 时两者会错开。
import { OtpAlgorithm } from '@yansongda/otp';
import { IItemConfig, NormConfig } from '../types/Item';

// 服务端与库共同认可的默认值
export const DEFAULT_PERIOD: number = 30;
export const DEFAULT_DIGITS: number = 6;
export const DEFAULT_ALGORITHM: OtpAlgorithm = OtpAlgorithm.SHA1;

// 与后端 Totp::period() 一致：仅正整数秒合法
export function normalizePeriod(period: number | undefined): number {
  if ('number' === typeof period && Number.isFinite(period) && Number.isInteger(period) && period > 0) {
    return period;
  }

  return DEFAULT_PERIOD;
}

// 与后端 Totp::digits() 一致：仅 6~8 位合法，其余按默认值算码
export function normalizeDigits(digits: number | undefined): number {
  if ('number' === typeof digits && Number.isInteger(digits) && digits >= 6 && digits <= 8) {
    return digits;
  }

  return DEFAULT_DIGITS;
}

// 与后端 Totp::algorithm() 一致：仅 SHA1/SHA256/SHA512 合法，其余按默认值算码
export function normalizeAlgorithm(algorithm: string | undefined): OtpAlgorithm {
  switch (algorithm) {
    case 'SHA256':
      return OtpAlgorithm.SHA256;
    case 'SHA512':
      return OtpAlgorithm.SHA512;
    default:
      return DEFAULT_ALGORITHM;
  }
}

// 服务端响应 → 归一化配置。secret 原样保留（可选：历史 / 异常响应可能没有），
// 是否「可端内算码」由 `NormConfig#secret` 是否非空决定。
// 入参允许已是 `NormConfig`（幂等：`ItemRuntime` 之间复制配置时直接透传）。
export function normalizeConfig(config: IItemConfig | NormConfig | undefined): NormConfig {
  const normalized: NormConfig = {
    period: normalizePeriod(config?.period),
    digits: normalizeDigits(config?.digits),
    algorithm: normalizeAlgorithm(config?.algorithm),
  };

  const secret: string | undefined = config?.secret;

  if ('string' === typeof secret && secret.length > 0) {
    normalized.secret = secret;
  }

  return normalized;
}

// ── 时间窗（前置条件：period 已由 normalizePeriod 保证为正整数秒）──

// 当前时间窗序号：变化即「该换验证码了」
export function stepOf(nowMs: number, period: number): number {
  return Math.floor(Math.floor(nowMs / 1000) / period);
}

// 当前窗口剩余整秒 ∈ [1, period]：窗口起点是 period、末尾是 1，永远不出现 0
export function remainingOf(nowMs: number, period: number): number {
  return period - (Math.floor(nowMs / 1000) % period);
}
