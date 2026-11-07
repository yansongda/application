/**
 * digits / algorithm 校验 + 取模补零（唯一取模点）。
 */
import { describe, expect, it } from "bun:test";
import {
  format,
  isValidAlgorithm,
  isValidDigits,
} from "../../src/otp/internal/digits";
import { expectCode } from "./helpers";

describe("digits", () => {
  it("format_6_7_8", () => {
    expect(format(287082, 6)).toBe("287082");
    expect(format(287082, 7)).toBe("0287082");
    expect(format(287082, 8)).toBe("00287082");
  });

  it("format_zeroPadsToFullWidth", () => {
    expect(format(0, 6)).toBe("000000");
    expect(format(7, 8)).toBe("00000007");
  });

  it("format_moduloOnlyOnce", () => {
    // 取模在 format 唯一发生点：10^digits 只截断一次，不做二次归一化
    expect(format(1000000, 6)).toBe("000000");
    expect(format(999999, 6)).toBe("999999");
  });

  it("format_invalidDigits_throws", () => {
    expectCode(() => format(0, 5), "INVALID_DIGITS");
    expectCode(() => format(0, 9), "INVALID_DIGITS");
    expectCode(() => format(0, 6.5), "INVALID_DIGITS");
  });

  it("isValidDigits_only_6_7_8", () => {
    expect(isValidDigits(6)).toBe(true);
    expect(isValidDigits(7)).toBe(true);
    expect(isValidDigits(8)).toBe(true);
    expect(isValidDigits(5)).toBe(false);
    expect(isValidDigits(9)).toBe(false);
  });

  it("isValidAlgorithm_only_three_values", () => {
    expect(isValidAlgorithm("SHA1")).toBe(true);
    expect(isValidAlgorithm("SHA256")).toBe(true);
    expect(isValidAlgorithm("SHA512")).toBe(true);
    expect(isValidAlgorithm("MD5" as "SHA1")).toBe(false);
  });
});
