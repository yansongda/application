/**
 * period 归一化（utils/totp.ts）：`@yansongda/miniprogram-otp` 内部要求正整数秒，
 * 脏缓存（0 / 小数 / 非数字）必须回落 30s，否则算码直接抛 INVALID_PERIOD。
 */
import { describe, expect, it } from "bun:test";
import { computeSnapshot, normalizePeriod } from "../../src/utils/totp";

describe("normalizePeriod", () => {
  it("keepsPositiveIntegers", () => {
    expect(normalizePeriod(1)).toBe(1);
    expect(normalizePeriod(30)).toBe(30);
    expect(normalizePeriod(60)).toBe(60);
  });

  it("fallsBackTo30ForInvalidValues", () => {
    const invalid = [
      undefined,
      0,
      -30,
      1.5,
      Number.NaN,
      Number.POSITIVE_INFINITY,
    ];

    for (const value of invalid) {
      expect(normalizePeriod(value)).toBe(30);
    }
  });

  it("computeSnapshot_toleratesDirtyPeriod", () => {
    const snapshot = computeSnapshot(
      "JBSWY3DPEHPK3PXP",
      0,
      6,
      "SHA1",
      1_700_000_000_000,
    );

    expect(snapshot.code).toMatch(/^\d{6}$/);
    expect(snapshot.remaining).toBeGreaterThan(0);
    expect(snapshot.remaining).toBeLessThanOrEqual(30);
  });
});
