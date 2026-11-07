/**
 * 哈希 / HMAC 原语测试：FIPS 180-4 + RFC 2202/4231 向量。
 * 同时覆盖 provider 映射（算法名 → 哈希函数 / 块大小），防止接错算法。
 */
import { describe, expect, it } from "bun:test";
import { OtpError } from "../../src/otp/errors";
import { PureJsHmac } from "../../src/otp/internal/crypto-source";
import { hmac } from "../../src/otp/internal/hmac";
import { sha1 } from "../../src/otp/internal/sha1";
import { sha256 } from "../../src/otp/internal/sha256";
import { sha512 } from "../../src/otp/internal/sha512";
import {
  HASH_VECTORS,
  HMAC_VECTORS,
  SHA1_DIGESTS,
  SHA256_DIGESTS,
  SHA512_DIGESTS,
  toHex,
} from "./vectors";

describe("hash", () => {
  for (const v of HASH_VECTORS) {
    it(`sha1_${v.label}`, () => {
      expect(toHex(sha1(v.bytes))).toBe(SHA1_DIGESTS[v.label]);
    });
    it(`sha256_${v.label}`, () => {
      expect(toHex(sha256(v.bytes))).toBe(SHA256_DIGESTS[v.label]);
    });
    it(`sha512_${v.label}`, () => {
      expect(toHex(sha512(v.bytes))).toBe(SHA512_DIGESTS[v.label]);
    });
  }
});

describe("hmac", () => {
  for (const v of HMAC_VECTORS) {
    it(`${v.label}_sha1`, () => {
      expect(toHex(hmac(sha1, 64, v.key, v.message))).toBe(v.sha1);
    });
    it(`${v.label}_sha256`, () => {
      expect(toHex(hmac(sha256, 64, v.key, v.message))).toBe(v.sha256);
    });
    it(`${v.label}_sha512`, () => {
      expect(toHex(hmac(sha512, 128, v.key, v.message))).toBe(v.sha512);
    });
  }
});

describe("provider", () => {
  const provider = new PureJsHmac();

  for (const v of HMAC_VECTORS) {
    it(`${v.label}_provider_mapping`, () => {
      expect(toHex(provider.sign("SHA1", v.key, v.message))).toBe(v.sha1);
      expect(toHex(provider.sign("SHA256", v.key, v.message))).toBe(v.sha256);
      expect(toHex(provider.sign("SHA512", v.key, v.message))).toBe(v.sha512);
    });
  }

  it("provider_wrapsUnexpectedFailureAsCryptoFailed", () => {
    // 非法算法值穿透（仅测试构造）：固定错误码，不泄漏底层错误
    let thrown: unknown = null;
    try {
      provider.sign("MD5" as "SHA1", new Uint8Array(1), new Uint8Array(1));
    } catch (e) {
      thrown = e;
    }
    expect(thrown instanceof OtpError).toBe(true);
    expect((thrown as OtpError).code).toBe("CRYPTO_FAILED");
  });
});
