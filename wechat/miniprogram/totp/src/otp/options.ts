/**
 * 对外选项 / 返回类型（DTO）。
 *
 * 字段名与可选性对齐 ohos-otp 的冻结契约：v1 起仅允许新增可选字段。
 * 差异：ArkTS 用 enum，TS 侧用 const 对象 + 联合类型，
 * 这样 "SHA1" 字面量与 OtpAlgorithm.SHA1 两种写法都可用（枚举在 TS 中不可由字面量赋值）。
 */

/** 算法（字符串值，RFC 6238 §1.2）。 */
export const OtpAlgorithm = {
  SHA1: "SHA1",
  SHA256: "SHA256",
  SHA512: "SHA512",
} as const;

export type OtpAlgorithm = (typeof OtpAlgorithm)[keyof typeof OtpAlgorithm];

/** OTP 类型（otpauth URI 的 type 参数）。 */
export const OtpType = {
  TOTP: "totp",
  HOTP: "hotp",
} as const;

export type OtpType = (typeof OtpType)[keyof typeof OtpType];

/** HMAC 通用选项（HOTP / TOTP 共用字段）。 */
export interface HmacOptions {
  /** 必填；base32，宽松解析（容忍大小写 / 空白 / 填充）。 */
  secret: string;
  /** 默认 SHA1。 */
  algorithm?: OtpAlgorithm;
  /** 默认 6；仅允许 6 | 7 | 8（RFC 4226 §5.3）。 */
  digits?: number;
  /** 默认 0 = 不强制；设 128 启用 RFC 4226 §4 R6 校验。 */
  minSecretBits?: number;
}

/** TOTP 选项（RFC 6238）。 */
export interface TotpOptions extends HmacOptions {
  /** 默认 30（RFC 6238 §5.2 推荐值），正整数秒。 */
  period?: number;
  /** 默认 0（RFC 6238 §4.1 的 T0，单位秒）。 */
  t0?: number;
  /** 默认 0；时钟偏移补偿，仅 TOTP 有效（见 syncClockOffset）。 */
  clockOffsetMs?: number;
  /** 仅用于 toURI()。 */
  issuer?: string;
  /** 仅用于 toURI()。 */
  account?: string;
}

/** HOTP 选项（RFC 4226）。 */
export interface HotpOptions extends HmacOptions {
  /** 默认 0。 */
  counter?: number;
  /** 仅用于 toURI()。 */
  issuer?: string;
  /** 仅用于 toURI()。 */
  account?: string;
}

/** verify 校验选项。 */
export interface VerifyOptions {
  /** epoch ms，仅 TOTP，默认 Date.now()。 */
  timestamp?: number;
  /** 仅 HOTP，默认构造时的 counter。 */
  counter?: number;
  /** 漂移窗口（步），默认 0。 */
  window?: number;
}

/**
 * 解析选项（Secret.fromBase32 与 OTPAuthURI.parse 共用，语义一致）。
 * 缺省（undefined / false）保持宽松行为。
 */
export interface ParseOptions {
  /** true：要求归一化后为规范 base32（尾长 ∈ {0,2,4,5,7} 且填充位为 0），否则 INVALID_BASE32_PADDING。 */
  strict?: boolean;
}

/** otpauth URI 解析 / 构建的中间参数形态。 */
export interface OtpAuthParams {
  type: OtpType;
  /** 规范化大写无填充 base32。 */
  secret: string;
  algorithm: OtpAlgorithm;
  digits: number;
  /** 仅 TOTP，默认 30。 */
  period?: number;
  /** 仅 HOTP，默认 0。 */
  counter?: number;
  issuer?: string;
  account?: string;
  label?: string;
}
