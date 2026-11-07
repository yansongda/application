/**
 * 严格 base64（RFC 4648 标准字母表 + 规范 padding）。
 *
 * 规范 §7 要求解码器拒绝：含空白/换行、非标准字母表、padding 缺失或多余、
 * 长度非 4 的倍数——因此不使用 atob（小程序无该 API），也不复用 wx 平台能力，
 * 保证纯函数可测且两端对同一坏串给出同一错误。
 */
import { BackupError, BackupErrorCode } from "./spec";

const ALPHABET =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

const DECODE_TABLE: Record<string, number> = {};

for (let i = 0; i < ALPHABET.length; i++) {
  DECODE_TABLE[ALPHABET[i]] = i;
}

const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;

/** 严格解码：任何不合规输入抛 E_STRUCTURE；返回新分配的字节数组。 */
export const decodeBase64Strict = (input: string): Uint8Array => {
  if (input.length === 0 || input.length % 4 !== 0) {
    throw new BackupError({
      code: BackupErrorCode.E_STRUCTURE,
      detail: "base64 长度非法",
    });
  }

  if (!BASE64_PATTERN.test(input)) {
    throw new BackupError({
      code: BackupErrorCode.E_STRUCTURE,
      detail: "base64 字符或 padding 非法",
    });
  }

  const padding = input.endsWith("==") ? 2 : input.endsWith("=") ? 1 : 0;
  const dataLength = input.length - padding;

  if (dataLength % 4 === 1) {
    throw new BackupError({
      code: BackupErrorCode.E_STRUCTURE,
      detail: "base64 尾块非法",
    });
  }

  const outputLength = (input.length / 4) * 3 - padding;
  const out = new Uint8Array(outputLength);
  let outIndex = 0;

  for (let i = 0; i < input.length; i += 4) {
    const c0 = DECODE_TABLE[input[i]];
    const c1 = DECODE_TABLE[input[i + 1]];
    const c2 = i + 2 < dataLength ? DECODE_TABLE[input[i + 2]] : 0;
    const c3 = i + 3 < dataLength ? DECODE_TABLE[input[i + 3]] : 0;

    if (
      c0 === undefined ||
      c1 === undefined ||
      c2 === undefined ||
      c3 === undefined
    ) {
      throw new BackupError({
        code: BackupErrorCode.E_STRUCTURE,
        detail: "base64 字符非法",
      });
    }

    out[outIndex++] = (c0 << 2) | (c1 >>> 4);

    if (outIndex < outputLength) {
      out[outIndex++] = ((c1 & 0x0f) << 4) | (c2 >>> 2);
    }

    if (outIndex < outputLength) {
      out[outIndex++] = ((c2 & 0x03) << 6) | c3;
    }
  }

  return out;
};

/** 标准 base64 编码（带规范 padding）。 */
export const encodeBase64 = (bytes: Uint8Array): string => {
  let out = "";

  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;

    out += ALPHABET[b0 >>> 2];
    out += ALPHABET[((b0 & 0x03) << 4) | (b1 >>> 4)];

    if (i + 1 < bytes.length) {
      out += ALPHABET[((b1 & 0x0f) << 2) | (b2 >>> 6)];
    } else {
      out += "=";
    }

    if (i + 2 < bytes.length) {
      out += ALPHABET[b2 & 0x3f];
    } else {
      out += "=";
    }
  }

  return out;
};
