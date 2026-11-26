// TOTP 条目配置的**归一化唯一入口**（纯逻辑，无 ArkUI 依赖，可在 `entry/src/test` 单测）。
//
// 为什么必须在入模型那一刻归一化：
// - 后端 `Totp::period()/digits()/algorithm()` 只接受正整数秒 / 6~8 位 / SHA1|SHA256|SHA512，
//   非法值在库内直接抛 `INVALID_PERIOD` 等错误码；
// - 归一化若分散到每个读取点（`?? 30`、`?? 6`、`typeof === 'number'`），
//   迟早出现「同一份脏数据，首页按 30 走、详情页按 0 走」的不一致——
//   历史实现里 `progress ?? 30` 与 `progress ?? 0` 两处兜底并存就是这类问题。
// 因此：**归一化只做一次（`normalizeConfig`），之后 `NormConfig` 的每个字段都是确定值，下游不再兜底。**
import { OtpAlgorithm } from '@yansongda/otp';
import { IItemConfig, NormConfig } from '../types/Item';

// 服务端与库共同认可的默认值
export const DEFAULT_PERIOD: number = 30;
export const DEFAULT_DIGITS: number = 6;
export const DEFAULT_ALGORITHM: OtpAlgorithm = OtpAlgorithm.SHA1;

// 与后端 Totp::period() 一致：仅正整数秒合法。库内部按 floor(ms/1000) % period 计算 step，
// period 为 0 / 小数 / 非数字时要么抛 INVALID_PERIOD，要么让 progress 变成非整数。
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
