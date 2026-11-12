/**
 * otpauth URI 唯一包装层：扫码/导入解析、手动创建 build、TOTP 重建与错误文案映射。
 * 只允许 otpauth://totp/；HOTP 在本地拒绝（后端也只接受 otpauth://totp/）。
 * 手输密钥必须先经 Secret.fromBase32(strict) 校验——OTPAuthURI.build 的 secret 规范化是宽松的，
 * 不能当作唯一校验。本文件不依赖 wx / logger（logger 顶层执行 wx 调用，纯逻辑模块不得引入）。
 */

import error from "@utils/error";
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

// 错误文案映射：键穷尽（库新增码时编译期报错），值 `undefined` 表示回落通用文案；绝不打印 secret
const OTP_ERROR_MESSAGES: Record<OtpErrorCode, string | undefined> = {
  EMPTY_SECRET: "密钥不符合 Base32 规范，请重新输入或扫码",
  INVALID_BASE32_CHAR: "密钥不符合 Base32 规范，请重新输入或扫码",
  INVALID_BASE32_PADDING: "密钥不符合 Base32 规范，请重新输入或扫码",
  SECRET_TOO_SHORT: "密钥不符合 Base32 规范，请重新输入或扫码",
  SECRET_TOO_WEAK: "密钥不符合 Base32 规范，请重新输入或扫码",
  INVALID_ALGORITHM: "配置信息不合法",
  INVALID_DIGITS: "配置信息不合法",
  INVALID_PERIOD: "配置信息不合法",
  INVALID_T0: "配置信息不合法",
  // 以下码当前应用流程不可达（verify / crypto 路径），保持原有通用文案
  INVALID_WINDOW: undefined,
  INVALID_COUNTER: undefined,
  INVALID_TIMESTAMP: undefined,
  INVALID_TOKEN: undefined,
  CRYPTO_FAILED: undefined,
  CRYPTO_NOT_INITIALIZED: undefined,
  NOT_IMPLEMENTED: undefined,
  INVALID_OTPAUTH_URI: "二维码不是有效的 otpauth 链接",
  UNSUPPORTED_OTPAUTH_TYPE: "仅支持 TOTP 二维码",
};

const describeOtpError = (e: unknown): string => {
  if (e instanceof OtpError) {
    // 运行时可能有库新增码未同步（类型层已穷尽，运行层兜底）
    return OTP_ERROR_MESSAGES[e.code] ?? error.getErrorMessage(e);
  }

  return error.getErrorMessage(e);
};

export { buildTotpUri, describeOtpError, parseTotpUri, rebuildTotpUri };
