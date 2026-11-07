/**
 * 解耦层：HMAC / 随机源接口 + 注册表（无平台依赖）。
 *
 * 公开类与 Secret 只依赖本层，经注册表取默认实现；
 * 真实实现见 internal/crypto-source.ts —— 它是唯一允许接触平台能力的文件。
 * 这样测试可在纯 JS 环境注入 fixture，运行时再注册默认实现。
 */
import { OtpError, OtpErrorCode } from "../errors";
import type { OtpAlgorithm } from "../options";

/** HMAC 抽象接口。 */
export interface HmacProvider {
  sign(
    algorithm: OtpAlgorithm,
    key: Uint8Array,
    message: Uint8Array,
  ): Uint8Array;
}

/** 随机数抽象接口。 */
export interface RandomSource {
  random(bytes: number): Uint8Array;
}

// 模块级单例（默认未注册；由 installCryptoDefaults 或测试注入）
let hmacProvider: HmacProvider | null = null;
let randomSource: RandomSource | null = null;

/** 注册 HMAC 实现（幂等覆盖）。 */
export function registerHmac(provider: HmacProvider): void {
  hmacProvider = provider;
}

/** 取用 HMAC 实现；未注册时抛 CRYPTO_NOT_INITIALIZED。 */
export function requireHmac(): HmacProvider {
  if (hmacProvider === null) {
    throw new OtpError(
      OtpErrorCode.CRYPTO_NOT_INITIALIZED,
      "CRYPTO_NOT_INITIALIZED",
    );
  }
  return hmacProvider;
}

/**
 * 注册随机源实现（幂等覆盖）。
 * 微信小程序没有同步密码学随机 API（wx.getRandomValues 是异步的），
 * 因此默认实现不注册随机源；需要 Secret.generate() 的调用方须自行注入同步 RandomSource。
 */
export function registerRandom(source: RandomSource): void {
  randomSource = source;
}

/** 取用随机源；未注册时抛 CRYPTO_NOT_INITIALIZED。 */
export function requireRandom(): RandomSource {
  if (randomSource === null) {
    throw new OtpError(
      OtpErrorCode.CRYPTO_NOT_INITIALIZED,
      "CRYPTO_NOT_INITIALIZED",
    );
  }
  return randomSource;
}

/** 清空已注册的 HMAC 与随机源实现，恢复到「未注册」状态（仅测试使用）。 */
export function reset(): void {
  hmacProvider = null;
  randomSource = null;
}
