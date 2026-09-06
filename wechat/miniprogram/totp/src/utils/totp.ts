import { TOTP } from "../vendor/otpauth.esm.min.js";

// 缓存已构建的 TOTP 实例，避免每次算码重复解析 secret 与重建实例。
// 键为 `${period}:${secret}`，条目数随用户密钥数增长，量级有限。
const totpInstanceCache = new Map<string, TOTP>();

const getTotpInstance = (secret: string, period: number): TOTP => {
  const key = `${period}:${secret}`;
  const cached = totpInstanceCache.get(key);

  if (typeof cached !== "undefined") {
    return cached;
  }

  // 与后端 build_noncompliant 行为对齐：强制 SHA1 + 6 位，忽略 URI 中的 algorithm/digits。
  const instance = new TOTP({
    secret,
    algorithm: "SHA1",
    digits: 6,
    period,
  });

  totpInstanceCache.set(key, instance);

  return instance;
};

const computeCode = (
  secret: string,
  period: number,
  timestamp: number,
): string => {
  return getTotpInstance(secret, period).generate({ timestamp });
};

export { computeCode };
