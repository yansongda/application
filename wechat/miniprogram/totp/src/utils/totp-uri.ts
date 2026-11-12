/**
 * otpauth URI 唯一包装层：扫码/导入解析、手动创建 build、TOTP 重建与错误文案映射。
 * 只允许 otpauth://totp/；HOTP 在本地拒绝（后端也只接受 otpauth://totp/）。
 * 手输密钥必须先经 Secret.fromBase32(strict) 校验——OTPAuthURI.build 的 secret 规范化是宽松的，
 * 不能当作唯一校验。本文件不依赖 wx / logger（logger 顶层执行 wx 调用，纯逻辑模块不得引入）。
 */
import {
  OTPAuthURI,
  type OtpAuthParams,
  OtpError,
  OtpErrorCode,
  OtpType,
  Secret,
} from "@yansongda/miniprogram-otp";
import type { TotpAlgorithm } from "../types/totp";

export interface TotpUriInput {
  issuer: string;
  account: string;
  secret: string;
  period: number;
  digits: number;
  algorithm: TotpAlgorithm;
}

// 扫码/导入：strict 拒绝被截断的密钥；非 TOTP 一律拒绝
const parseTotpUri = (raw: string): OtpAuthParams => {
  const p = OTPAuthURI.parse(raw, { strict: true });

  if (p.type !== OtpType.TOTP) {
    throw new OtpError(
      OtpErrorCode.UNSUPPORTED_OTPAUTH_TYPE,
      "UNSUPPORTED_OTPAUTH_TYPE",
    );
  }

  return p;
};

// 手动创建：strict 规范化后再 build（build 输出小写 otpauth://totp/...，默认 digits/period 省略）
const buildTotpUri = (input: TotpUriInput): string => {
  const secret = Secret.fromBase32(input.secret, { strict: true }).toBase32();

  return OTPAuthURI.build({
    type: OtpType.TOTP,
    secret,
    algorithm: input.algorithm,
    digits: input.digits,
    period: input.period,
    issuer: input.issuer,
    account: input.account,
  });
};

// 按解析结果重建规范 URI（大写 scheme 归一为小写）；非 TOTP 拒绝
const rebuildTotpUri = (p: OtpAuthParams): string => {
  if (p.type !== OtpType.TOTP) {
    throw new OtpError(
      OtpErrorCode.UNSUPPORTED_OTPAUTH_TYPE,
      "UNSUPPORTED_OTPAUTH_TYPE",
    );
  }

  return OTPAuthURI.build(p);
};

// 错误文案映射：按 code 分支，绝不打印 secret
const describeOtpError = (e: unknown): string => {
  if (e instanceof OtpError) {
    switch (e.code) {
      case OtpErrorCode.INVALID_BASE32_CHAR:
      case OtpErrorCode.INVALID_BASE32_PADDING:
      case OtpErrorCode.EMPTY_SECRET:
      case OtpErrorCode.SECRET_TOO_SHORT:
        return "密钥不符合 Base32 规范，请重新输入或扫码";
      case OtpErrorCode.UNSUPPORTED_OTPAUTH_TYPE:
        return "仅支持 TOTP 二维码";
      case OtpErrorCode.INVALID_ALGORITHM:
      case OtpErrorCode.INVALID_DIGITS:
      case OtpErrorCode.INVALID_PERIOD:
        return "配置信息不合法";
      case OtpErrorCode.INVALID_OTPAUTH_URI:
        return "二维码不是有效的 otpauth 链接";
      default:
        return "操作失败，请重试";
    }
  }

  return "操作失败，请重试";
};

export { buildTotpUri, describeOtpError, parseTotpUri, rebuildTotpUri };
