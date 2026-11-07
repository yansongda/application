import { expect } from "bun:test";
import { OtpError, type OtpErrorCode } from "../../src/otp/errors";

/** 期望抛出指定错误码（断言 code 比消息匹配更精确）。 */
export function expectCode(fn: () => unknown, code: OtpErrorCode): void {
  let thrown: unknown = null;
  try {
    fn();
  } catch (e) {
    thrown = e;
  }
  expect(thrown instanceof OtpError).toBe(true);
  expect((thrown as OtpError).code).toBe(code);
}
