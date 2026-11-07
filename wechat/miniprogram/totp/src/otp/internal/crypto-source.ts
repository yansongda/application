/**
 * 实现层：纯 JS HMAC provider（唯一接触「平台能力」的文件）。
 *
 * 微信小程序无 WebCrypto / SubtleCrypto，HMAC 只能纯 JS 实现；
 * 因此这里直接注册纯 JS 实现，不再区分 kit / 非 kit（TS 侧无 ArkTS 的静态 import 传递性限制）。
 * 随机源不在此注册：微信只有异步 wx.getRandomValues，无法满足同步 API 契约（见 crypto-provider.ts）。
 */
import { OtpError, OtpErrorCode } from "../errors";
import type { OtpAlgorithm } from "../options";
import { type HmacProvider, registerHmac } from "./crypto-provider";
import { hmac } from "./hmac";
import { sha1 } from "./sha1";
import { sha256 } from "./sha256";
import { sha512 } from "./sha512";

interface HashSpec {
  hash: (message: Uint8Array) => Uint8Array;
  blockSize: number;
}

const HASH_SPECS: Record<OtpAlgorithm, HashSpec> = {
  SHA1: { hash: sha1, blockSize: 64 },
  SHA256: { hash: sha256, blockSize: 64 },
  SHA512: { hash: sha512, blockSize: 128 },
};

/** 纯 JS HMAC 实现（同步链路）。 */
export class PureJsHmac implements HmacProvider {
  sign(
    algorithm: OtpAlgorithm,
    key: Uint8Array,
    message: Uint8Array,
  ): Uint8Array {
    try {
      const spec = HASH_SPECS[algorithm];
      return hmac(spec.hash, spec.blockSize, key, message);
    } catch (_e) {
      // 固定文案：不透传底层错误、不打日志、不含 key/message
      throw new OtpError(OtpErrorCode.CRYPTO_FAILED, "CRYPTO_FAILED");
    }
  }
}

/** 注册默认 HMAC 实现（只 new + 注册，不发起任何计算）。 */
export function installCryptoDefaults(): void {
  registerHmac(new PureJsHmac());
}
