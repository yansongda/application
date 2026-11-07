/**
 * @yansongda/otp（微信小程序版）全量 barrel（唯一对业务代码的入口）。
 *
 * 顶层导入并立即注册默认 HMAC 实现：与 ohos-otp 的 Index.ets 同构，
 * 消费者零配置（只 new 实现并注册，不发起任何计算）。
 * internal/* 与 provider 一律不导出（测试经深路径直接 import）。
 */
import { installCryptoDefaults } from "./internal/crypto-source";

// 幂等注册；仅构造对象并注册，不发起任何 HMAC 计算
installCryptoDefaults();

export { OtpError, OtpErrorCode } from "./errors";
export { HOTP } from "./hotp";
export type {
  HmacOptions,
  HotpOptions,
  OtpAuthParams,
  ParseOptions,
  TotpOptions,
  VerifyOptions,
} from "./options";
export { OtpAlgorithm, OtpType } from "./options";
export { OTPAuthURI } from "./otpauth-uri";
export { Secret } from "./secret";
export { TOTP } from "./totp";
