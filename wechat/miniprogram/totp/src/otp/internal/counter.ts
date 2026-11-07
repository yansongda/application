/**
 * 计数器 → 8 字节大端字节数组（纯函数，无平台依赖）。
 *
 * 不能用 << 直接拼 32 位：JS 位运算按 32 位有符号整数处理，而 RFC 6238 §4.2
 * 要求时间步支持超过 32 位，直接左移会溢出截断。因此拆 high/low 各 4 字节，逐字节取出。
 */
import { OtpError, OtpErrorCode } from "../errors";

const UINT32 = 2 ** 32;

export function isSafeCounter(value: number): boolean {
  return (
    Number.isInteger(value) && value >= 0 && value <= Number.MAX_SAFE_INTEGER
  );
}

export function toBytes(counter: number): Uint8Array {
  if (!isSafeCounter(counter)) {
    throw new OtpError(OtpErrorCode.INVALID_COUNTER, "INVALID_COUNTER");
  }

  const high = Math.floor(counter / UINT32);
  const low = counter % UINT32;

  const result = new Uint8Array(8);
  result[0] = (high >>> 24) & 0xff;
  result[1] = (high >>> 16) & 0xff;
  result[2] = (high >>> 8) & 0xff;
  result[3] = high & 0xff;
  result[4] = (low >>> 24) & 0xff;
  result[5] = (low >>> 16) & 0xff;
  result[6] = (low >>> 8) & 0xff;
  result[7] = low & 0xff;
  return result;
}
