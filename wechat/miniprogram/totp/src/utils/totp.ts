import type { TotpAlgorithm } from "types/totp";
// 微信运行时不做目录 index 解析（"../otp" 会被当成 otp.js），必须显式指向 barrel 文件
import { TOTP } from "../otp/index";

const DEFAULT_DIGITS = 6;
const DEFAULT_ALGORITHM: TotpAlgorithm = "SHA1";

// 与后端 Totp::digits() 一致：仅 6~8 合法，其余按默认值算码
const normalizeDigits = (digits: number | undefined): number => {
  return digits === 7 || digits === 8 ? digits : DEFAULT_DIGITS;
};

// 与后端 Totp::algorithm() 一致：仅 SHA1/SHA256/SHA512 合法，其余按默认值算码
const normalizeAlgorithm = (algorithm: string | undefined): TotpAlgorithm => {
  switch (algorithm) {
    case "SHA256":
      return "SHA256";
    case "SHA512":
      return "SHA512";
    default:
      return DEFAULT_ALGORITHM;
  }
};

// 缓存已构建的 TOTP 实例，避免每次算码重复解析 secret 与重建实例。
// 键为 `${algorithm}:${digits}:${period}:${secret}`，条目数随用户密钥数增长，量级有限。
const totpInstanceCache = new Map<string, TOTP>();

const getTotpInstance = (
  secret: string,
  period: number,
  digits: number | undefined,
  algorithm: string | undefined,
): TOTP => {
  const normalizedDigits = normalizeDigits(digits);
  const normalizedAlgorithm = normalizeAlgorithm(algorithm);
  const key = `${normalizedAlgorithm}:${normalizedDigits}:${period}:${secret}`;
  const cached = totpInstanceCache.get(key);

  if (typeof cached !== "undefined") {
    return cached;
  }

  // 按后端下发的净化值算码；旧缓存/旧后端缺字段时由 normalize* 回退 6 位 + SHA1。
  const instance = new TOTP({
    secret,
    algorithm: normalizedAlgorithm,
    digits: normalizedDigits,
    period,
  });

  totpInstanceCache.set(key, instance);

  return instance;
};

const computeCode = (
  secret: string,
  period: number,
  digits: number | undefined,
  algorithm: string | undefined,
  timestamp: number,
): string => {
  return getTotpInstance(secret, period, digits, algorithm).generate(timestamp);
};

// 一次构建实例，同时产出验证码、倒计时与环形进度，供列表/详情页展示
const computeSnapshot = (
  secret: string,
  period: number,
  digits: number | undefined,
  algorithm: string | undefined,
  timestamp: number,
): { code: string; remaining: number; progress: number } => {
  const instance = getTotpInstance(secret, period, digits, algorithm);

  return {
    code: instance.generate(timestamp),
    remaining: instance.remaining(timestamp),
    progress: instance.progress(timestamp),
  };
};

export { computeCode, computeSnapshot };
