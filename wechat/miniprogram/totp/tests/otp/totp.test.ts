/**
 * TOTP 公开类测试：RFC 6238 Appendix B 全量向量 + 时间偏移闭环 + 构造期校验 + URI 往返。
 */
import { describe, expect, it } from "bun:test";
import { TOTP } from "../../src/otp";
import { expectCode } from "./helpers";
import {
  RFC6238_SHA1,
  RFC6238_SHA256,
  RFC6238_SHA512,
  SEEDS,
  SHA256_C0_8DIGIT,
} from "./vectors";

describe("totp", () => {
  // A.3：X=30 / T0=0 / digits=8，三算法 × 6 时间点 = 18 条
  for (const v of RFC6238_SHA1) {
    it(`rfc6238_sha1_t${v.timeSec}`, () => {
      expect(
        new TOTP({ secret: SEEDS.SHA1_BASE32, digits: 8 }).generate(
          v.timeSec * 1000,
        ),
      ).toBe(v.code8);
    });
  }
  for (const v of RFC6238_SHA256) {
    it(`rfc6238_sha256_t${v.timeSec}`, () => {
      expect(
        new TOTP({
          secret: SEEDS.SHA256_BASE32,
          algorithm: "SHA256",
          digits: 8,
        }).generate(v.timeSec * 1000),
      ).toBe(v.code8);
    });
  }
  for (const v of RFC6238_SHA512) {
    it(`rfc6238_sha512_t${v.timeSec}`, () => {
      expect(
        new TOTP({
          secret: SEEDS.SHA512_BASE32,
          algorithm: "SHA512",
          digits: 8,
        }).generate(v.timeSec * 1000),
      ).toBe(v.code8);
    });
  }

  it("public_api_full_chain", () => {
    expect(
      new TOTP({ secret: SEEDS.SHA1_BASE32, digits: 8 }).generate(59000),
    ).toBe("94287082");
  });

  it("digits6_period30_generate59000", () => {
    expect(
      new TOTP({ secret: SEEDS.SHA1_BASE32, digits: 6 }).generate(59000),
    ).toBe("287082");
  });

  it("remaining_59000", () => {
    expect(new TOTP({ secret: SEEDS.SHA1_BASE32 }).remaining(59000)).toBe(1);
  });

  it("progress_15000", () => {
    expect(new TOTP({ secret: SEEDS.SHA1_BASE32 }).progress(15000)).toBe(0.5);
  });

  it("verify_positive_delta0", () => {
    expect(
      new TOTP({ secret: SEEDS.SHA1_BASE32, digits: 6 }).verify("287082", {
        timestamp: 59000,
      }),
    ).toBe(0);
  });

  it("verify_negative_window0_prevStepCode", () => {
    expect(
      new TOTP({ secret: SEEDS.SHA1_BASE32, digits: 6 }).verify("755224", {
        timestamp: 59000,
      }),
    ).toBeNull();
  });

  it("verify_window_delta_minus1", () => {
    expect(
      new TOTP({ secret: SEEDS.SHA1_BASE32, digits: 6 }).verify("287082", {
        timestamp: 89000,
        window: 1,
      }),
    ).toBe(-1);
  });

  it("verify_window_delta_plus1", () => {
    expect(
      new TOTP({ secret: SEEDS.SHA1_BASE32, digits: 6 }).verify("287082", {
        timestamp: 1000,
        window: 1,
      }),
    ).toBe(1);
  });

  it("verify_appliesClockOffset", () => {
    const t = new TOTP({ secret: SEEDS.SHA1_BASE32, digits: 6 });
    t.syncClockOffset(1);
    expect(t.clockOffsetMs).toBe(30000);
    expect(t.verify("359152", { timestamp: 59000 })).toBe(0);
  });

  it("syncClockOffset_closure_slowLocal", () => {
    const t = new TOTP({ secret: SEEDS.SHA1_BASE32, digits: 6 });
    const delta = t.verify("359152", { timestamp: 59000, window: 1 });
    expect(delta).toBe(1);
    t.syncClockOffset(delta as number);
    expect(t.clockOffsetMs).toBe(30000);
    expect(t.generate(59000)).toBe("359152");
    expect(t.verify("359152", { timestamp: 59000 })).toBe(0);
  });

  it("syncClockOffset_closure_fastLocal", () => {
    const t = new TOTP({ secret: SEEDS.SHA1_BASE32, digits: 6 });
    const delta = t.verify("287082", { timestamp: 89000, window: 1 });
    expect(delta).toBe(-1);
    t.syncClockOffset(delta as number);
    expect(t.clockOffsetMs).toBe(-30000);
    expect(t.generate(89000)).toBe("287082");
    expect(t.verify("287082", { timestamp: 89000 })).toBe(0);
  });

  it("syncClockOffset_repeatAccumulates", () => {
    const t = new TOTP({ secret: SEEDS.SHA1_BASE32, digits: 6 });
    t.syncClockOffset(1);
    t.syncClockOffset(1);
    expect(t.clockOffsetMs).toBe(60000);
    t.syncClockOffset(-3);
    expect(t.clockOffsetMs).toBe(-30000);
  });

  it("syncClockOffset_nonInteger_throws", () => {
    expectCode(
      () => new TOTP({ secret: SEEDS.SHA1_BASE32 }).syncClockOffset(1.5),
      "INVALID_WINDOW",
    );
  });

  it("t0_1_period30_timestamp31000", () => {
    expect(
      new TOTP({
        secret: SEEDS.SHA1_BASE32,
        digits: 8,
        period: 30,
        t0: 1,
      }).generate(31000),
    ).toBe("94287082");
  });

  it("fromURI_period60_sha256_counter0", () => {
    // period=60 → generate(59000) 的 counter = floor(59/60) = 0（勿与 counter=1 的 46119246 混淆）
    const t = TOTP.fromURI(
      `otpauth://totp/alice?secret=${SEEDS.SHA256_BASE32}&algorithm=SHA256&digits=8&period=60`,
    );
    expect(t.generate(59000)).toBe(SHA256_C0_8DIGIT);
  });

  it("toURI_verbatim", () => {
    expect(new TOTP({ secret: SEEDS.SHA1_BASE32, digits: 8 }).toURI()).toBe(
      "otpauth://totp/?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&algorithm=SHA1&digits=8",
    );
  });

  it("fromURI_roundtrip_generate_consistent", () => {
    const original = new TOTP({
      secret: SEEDS.SHA256_BASE32,
      algorithm: "SHA256",
      digits: 8,
      period: 60,
    });
    const restored = TOTP.fromURI(original.toURI());
    expect(restored.generate(59000)).toBe(original.generate(59000));
    expect(restored.generate(59000)).toBe(SHA256_C0_8DIGIT);
  });

  it("fromURI_hotpType_throws", () => {
    expectCode(
      () =>
        TOTP.fromURI(
          `otpauth://hotp/alice?secret=${SEEDS.SHA1_BASE32}&counter=0`,
        ),
      "UNSUPPORTED_OTPAUTH_TYPE",
    );
  });

  it("ctor_digits5_throws", () => {
    expectCode(
      () => new TOTP({ secret: SEEDS.SHA1_BASE32, digits: 5 }),
      "INVALID_DIGITS",
    );
  });

  it("ctor_period0_throws", () => {
    expectCode(
      () => new TOTP({ secret: SEEDS.SHA1_BASE32, period: 0 }),
      "INVALID_PERIOD",
    );
  });

  it("ctor_periodNeg_throws", () => {
    expectCode(
      () => new TOTP({ secret: SEEDS.SHA1_BASE32, period: -30 }),
      "INVALID_PERIOD",
    );
  });

  it("ctor_t0Neg1_throws", () => {
    expectCode(
      () => new TOTP({ secret: SEEDS.SHA1_BASE32, t0: -1 }),
      "INVALID_T0",
    );
  });

  it("ctor_t0Fraction_throws", () => {
    expectCode(
      () => new TOTP({ secret: SEEDS.SHA1_BASE32, t0: 1.5 }),
      "INVALID_T0",
    );
  });

  it("ctor_clockOffsetNaN_throws", () => {
    expectCode(
      () => new TOTP({ secret: SEEDS.SHA1_BASE32, clockOffsetMs: Number.NaN }),
      "INVALID_TIMESTAMP",
    );
  });

  it("ctor_clockOffsetInfinity_throws", () => {
    expectCode(
      () =>
        new TOTP({
          secret: SEEDS.SHA1_BASE32,
          clockOffsetMs: Number.POSITIVE_INFINITY,
        }),
      "INVALID_TIMESTAMP",
    );
  });

  it("ctor_algorithmInvalid_throws", () => {
    expectCode(
      () => new TOTP({ secret: SEEDS.SHA1_BASE32, algorithm: "MD5" as "SHA1" }),
      "INVALID_ALGORITHM",
    );
  });

  it("ctor_minSecretBits128_80bit_throws", () => {
    expectCode(
      () => new TOTP({ secret: "JBSWY3DPEHPK3PXP", minSecretBits: 128 }),
      "SECRET_TOO_WEAK",
    );
  });

  it("ctor_minSecretBits128_160bit_ok", () => {
    expect(
      new TOTP({
        secret: SEEDS.SHA1_BASE32,
        digits: 6,
        minSecretBits: 128,
      }).generate(59000),
    ).toBe("287082");
  });

  it("timeInputs_invalid_throw", () => {
    const t = new TOTP({ secret: SEEDS.SHA1_BASE32 });
    expectCode(() => t.generate(0), "INVALID_TIMESTAMP");
    expectCode(() => t.remaining(0), "INVALID_TIMESTAMP");
    expectCode(() => t.progress(-1), "INVALID_TIMESTAMP");
  });
});
