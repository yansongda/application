/**
 * HOTP 公开类测试：A.2 / A.4 / A.5 / A.6 向量 + 错误码。
 * 默认 provider 由 src/otp/index 的 installCryptoDefaults() 注册。
 */
import { describe, expect, it } from "bun:test";
import { HOTP } from "../../src/otp";
import { expectCode } from "./helpers";
import { BOUNDARY_COUNTERS, RFC4226_SHA1_6DIGIT, SEEDS } from "./vectors";

describe("hotp", () => {
  for (const v of RFC4226_SHA1_6DIGIT) {
    it(`rfc4226_counter_${v.counter}`, () => {
      expect(
        new HOTP({ secret: SEEDS.SHA1_BASE32, counter: v.counter }).generate(),
      ).toBe(v.code);
    });
  }

  it("generate_override_counter1_digits8", () => {
    expect(new HOTP({ secret: SEEDS.SHA1_BASE32, digits: 8 }).generate(1)).toBe(
      "94287082",
    );
  });

  it("digits7_counter1", () => {
    expect(
      new HOTP({ secret: SEEDS.SHA1_BASE32, digits: 7, counter: 1 }).generate(),
    ).toBe("4287082");
  });

  // A.4 边界 counter（RFC 6238 §4.2：时间步必须支持超过 32 位）
  for (const v of BOUNDARY_COUNTERS) {
    it(`boundary_${v.counter}_sha1`, () => {
      expect(
        new HOTP({ secret: SEEDS.SHA1_BASE32, counter: v.counter }).generate(),
      ).toBe(v.sha1.code6);
      expect(
        new HOTP({
          secret: SEEDS.SHA1_BASE32,
          digits: 8,
          counter: v.counter,
        }).generate(),
      ).toBe(v.sha1.code8);
    });
    it(`boundary_${v.counter}_sha256`, () => {
      expect(
        new HOTP({
          secret: SEEDS.SHA256_BASE32,
          algorithm: "SHA256",
          counter: v.counter,
        }).generate(),
      ).toBe(v.sha256.code6);
      expect(
        new HOTP({
          secret: SEEDS.SHA256_BASE32,
          algorithm: "SHA256",
          digits: 8,
          counter: v.counter,
        }).generate(),
      ).toBe(v.sha256.code8);
    });
    it(`boundary_${v.counter}_sha512`, () => {
      expect(
        new HOTP({
          secret: SEEDS.SHA512_BASE32,
          algorithm: "SHA512",
          counter: v.counter,
        }).generate(),
      ).toBe(v.sha512.code6);
      expect(
        new HOTP({
          secret: SEEDS.SHA512_BASE32,
          algorithm: "SHA512",
          digits: 8,
          counter: v.counter,
        }).generate(),
      ).toBe(v.sha512.code8);
    });
  }

  it("toURI_verbatim", () => {
    expect(new HOTP({ secret: SEEDS.SHA1_BASE32, counter: 0 }).toURI()).toBe(
      "otpauth://hotp/?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&algorithm=SHA1&counter=0",
    );
  });

  it("fromURI_roundtrip_generate_consistent", () => {
    const original = new HOTP({
      secret: SEEDS.SHA1_BASE32,
      digits: 8,
      counter: 1,
      issuer: "ACME Co",
      account: "alice",
    });
    const restored = HOTP.fromURI(original.toURI());
    expect(restored.generate()).toBe(original.generate());
    expect(restored.generate()).toBe("94287082");
  });

  it("verify_positive_delta0", () => {
    expect(
      new HOTP({ secret: SEEDS.SHA1_BASE32, counter: 1 }).verify("287082"),
    ).toBe(0);
  });

  it("verify_window_delta_minus1", () => {
    expect(
      new HOTP({ secret: SEEDS.SHA1_BASE32, counter: 2 }).verify("287082", {
        window: 1,
      }),
    ).toBe(-1);
  });

  it("verify_negative_window0_prevStepCode", () => {
    expect(
      new HOTP({ secret: SEEDS.SHA1_BASE32, counter: 1 }).verify("755224"),
    ).toBeNull();
  });

  it("verify_counterNegative_throws", () => {
    expectCode(
      () =>
        new HOTP({ secret: SEEDS.SHA1_BASE32, counter: 1 }).verify("287082", {
          counter: -5,
          window: 1,
        }),
      "INVALID_COUNTER",
    );
  });

  it("ctor_digits5_throws", () => {
    expectCode(
      () => new HOTP({ secret: SEEDS.SHA1_BASE32, digits: 5 }),
      "INVALID_DIGITS",
    );
  });

  it("ctor_counterNeg1_throws", () => {
    expectCode(
      () => new HOTP({ secret: SEEDS.SHA1_BASE32, counter: -1 }),
      "INVALID_COUNTER",
    );
  });

  it("ctor_algorithmInvalid_throws", () => {
    expectCode(
      () => new HOTP({ secret: SEEDS.SHA1_BASE32, algorithm: "MD5" as "SHA1" }),
      "INVALID_ALGORITHM",
    );
  });

  it("ctor_minSecretBits128_80bit_throws", () => {
    expectCode(
      () => new HOTP({ secret: "JBSWY3DPEHPK3PXP", minSecretBits: 128 }),
      "SECRET_TOO_WEAK",
    );
  });

  it("ctor_minSecretBits128_160bit_ok", () => {
    expect(
      new HOTP({ secret: SEEDS.SHA1_BASE32, minSecretBits: 128 }).generate(),
    ).toBe("755224");
  });

  it("fromURI_totpType_throws", () => {
    expectCode(
      () => HOTP.fromURI(`otpauth://totp/alice?secret=${SEEDS.SHA1_BASE32}`),
      "UNSUPPORTED_OTPAUTH_TYPE",
    );
  });
});
