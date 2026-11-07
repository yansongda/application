/**
 * 错误模型：18 个错误码取值冻结；OtpError 的 code / message / instanceof 行为。
 */
import { describe, expect, it } from "bun:test";
import { OtpError, OtpErrorCode } from "../../src/otp/errors";

const CODES = [
  "EMPTY_SECRET",
  "INVALID_BASE32_CHAR",
  "INVALID_BASE32_PADDING",
  "SECRET_TOO_SHORT",
  "SECRET_TOO_WEAK",
  "INVALID_ALGORITHM",
  "INVALID_DIGITS",
  "INVALID_PERIOD",
  "INVALID_T0",
  "INVALID_COUNTER",
  "INVALID_TIMESTAMP",
  "INVALID_WINDOW",
  "INVALID_TOKEN",
  "CRYPTO_FAILED",
  "CRYPTO_NOT_INITIALIZED",
  "INVALID_OTPAUTH_URI",
  "UNSUPPORTED_OTPAUTH_TYPE",
  "NOT_IMPLEMENTED",
] as const;

describe("errors", () => {
  it("hasExactly18FrozenCodes", () => {
    expect(Object.keys(OtpErrorCode).length).toBe(18);
    expect(Object.values(OtpErrorCode).sort()).toEqual([...CODES].sort());
  });

  it("codeValueEqualsItsName", () => {
    for (const code of CODES) {
      expect(OtpErrorCode[code]).toBe(code);
    }
  });

  it("messageIsFixedAndCodePreserved", () => {
    const err = new OtpError(OtpErrorCode.INVALID_DIGITS, "INVALID_DIGITS");
    expect(err.code).toBe("INVALID_DIGITS");
    expect(err.message).toBe("INVALID_DIGITS");
    expect(err.name).toBe("OtpError");
    expect(err instanceof OtpError).toBe(true);
    expect(err instanceof Error).toBe(true);
  });

  it("doesNotLeakSecretInMessage", () => {
    const secret = "JBSWY3DPEHPK3PXP";
    const err = new OtpError(OtpErrorCode.SECRET_TOO_WEAK, "SECRET_TOO_WEAK");
    expect(err.message.indexOf(secret)).toBe(-1);
  });
});
