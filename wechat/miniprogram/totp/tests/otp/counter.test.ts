/**
 * counter → 8 字节大端：A.5 对照表 + 边界（2^32 / 2^53-1）。
 */
import { describe, expect, it } from "bun:test";
import { isSafeCounter, toBytes } from "../../src/otp/internal/counter";
import { expectCode } from "./helpers";
import { COUNTER_BYTES, toHex } from "./vectors";

describe("counter", () => {
  for (const v of COUNTER_BYTES) {
    it(`counter_${v.counter}`, () => {
      expect(toHex(toBytes(v.counter))).toBe(v.hex);
    });
  }

  it("counter_negative_throws", () => {
    expectCode(() => toBytes(-1), "INVALID_COUNTER");
  });

  it("counter_fraction_throws", () => {
    expectCode(() => toBytes(1.5), "INVALID_COUNTER");
  });

  it("counter_overMaxSafeInteger_throws", () => {
    expectCode(() => toBytes(9007199254740992), "INVALID_COUNTER");
  });

  it("isSafeCounter_boundaries", () => {
    expect(isSafeCounter(0)).toBe(true);
    expect(isSafeCounter(9007199254740991)).toBe(true);
    expect(isSafeCounter(-1)).toBe(false);
    expect(isSafeCounter(1.5)).toBe(false);
    expect(isSafeCounter(Number.NaN)).toBe(false);
  });
});
