/**
 * Secret：规范化 / 字节视图 / 随机生成（注册表）/ toJSON 脱敏。
 */
import { afterEach, describe, expect, it } from "bun:test";
import { decode } from "../../src/otp/internal/base32";
import { registerRandom, reset } from "../../src/otp/internal/crypto-provider";
import { installCryptoDefaults } from "../../src/otp/internal/crypto-source";
import { Secret } from "../../src/otp/secret";
import { expectCode } from "./helpers";
import { asciiBytes, bytesEqual, SEEDS } from "./vectors";

afterEach(() => {
  reset();
  installCryptoDefaults();
});

describe("secret", () => {
  it("fromBase32_lenientNormalization", () => {
    const reference = Secret.fromBase32(SEEDS.SHA1_BASE32);
    expect(reference.toBase32()).toBe(SEEDS.SHA1_BASE32);
    expect(reference.byteLength).toBe(20);
    expect(reference.bitLength).toBe(160);
    const lower = Secret.fromBase32(`  ${SEEDS.SHA1_BASE32.toLowerCase()}==\n`);
    expect(lower.toBase32()).toBe(SEEDS.SHA1_BASE32);
    expect(bytesEqual(lower.bytes, reference.bytes)).toBe(true);
  });

  it("fromBase32_strictAcceptsCanonical", () => {
    expect(Secret.fromBase32("MY", { strict: true }).toBase32()).toBe("MY");
    expect(Secret.fromBase32("MY======", { strict: true }).toBase32()).toBe(
      "MY",
    );
  });

  it("fromBase32_strictRejectsNonCanonical", () => {
    expectCode(
      () => Secret.fromBase32("MZXW6YT", { strict: true }),
      "INVALID_BASE32_PADDING",
    );
    expectCode(
      () => Secret.fromBase32("A", { strict: true }),
      "INVALID_BASE32_PADDING",
    );
  });

  it("fromBase32_emptyOrInvalid_throws", () => {
    expectCode(() => Secret.fromBase32(""), "EMPTY_SECRET");
    expectCode(() => Secret.fromBase32("   "), "EMPTY_SECRET");
    expectCode(() => Secret.fromBase32("AB1"), "INVALID_BASE32_CHAR");
    expectCode(() => Secret.fromBase32("A"), "SECRET_TOO_SHORT");
  });

  it("fromBytes_copiesInput", () => {
    const input = asciiBytes(SEEDS.SHA1);
    const secret = Secret.fromBytes(input);
    input[0] = 0x00;
    expect(secret.toBase32()).toBe(SEEDS.SHA1_BASE32);
  });

  it("bytes_returnsCopy", () => {
    const secret = Secret.fromBase32(SEEDS.SHA1_BASE32);
    const view = secret.bytes;
    view[0] = 0x00;
    expect(secret.toBase32()).toBe(SEEDS.SHA1_BASE32);
    expect(secret.bytes[0]).toBe(decode(SEEDS.SHA1_BASE32)[0]);
  });

  it("fromBytes_empty_throws", () => {
    expectCode(() => Secret.fromBytes(new Uint8Array(0)), "EMPTY_SECRET");
  });

  it("generate_withoutRegisteredRandom_throws", () => {
    expectCode(() => Secret.generate(), "CRYPTO_NOT_INITIALIZED");
  });

  it("generate_withRegisteredRandom", () => {
    const bytes = new Uint8Array(20);
    for (let i = 0; i < bytes.length; i++) {
      bytes[i] = i + 1;
    }
    registerRandom({ random: (n: number) => bytes.slice(0, n) });
    const secret = Secret.generate();
    expect(secret.byteLength).toBe(20);
    expect(secret.toBase32()).toBe("AEBAGBAFAYDQQCIKBMGA2DQPCAIREEYU");
  });

  it("generate_invalidSize_throws", () => {
    registerRandom({ random: (n: number) => new Uint8Array(n) });
    expectCode(() => Secret.generate(0), "SECRET_TOO_WEAK");
    expectCode(() => Secret.generate(4097), "SECRET_TOO_WEAK");
    expectCode(() => Secret.generate(1.5), "SECRET_TOO_WEAK");
  });

  it("toJSON_redactsSecret", () => {
    const secret = Secret.fromBase32(SEEDS.SHA1_BASE32);
    expect(secret.toJSON()).toBe("[REDACTED]");
    expect(JSON.stringify({ s: secret })).toBe('{"s":"[REDACTED]"}');
    expect(JSON.stringify({ s: secret }).indexOf(SEEDS.SHA1_BASE32)).toBe(-1);
  });

  it("doesNotExposeToString", () => {
    // 刻意不实现 toString：模板字符串 / String() 不应泄漏密钥
    const secret = Secret.fromBase32(SEEDS.SHA1_BASE32);
    expect(String(secret) === "[object Object]").toBe(true);
  });
});
