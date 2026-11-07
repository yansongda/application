/**
 * RFC 4648 §6 base32 编解码（纯函数，无平台依赖）。
 * 字母表 A-Z + 2-7；encode 输出大写无填充；decode 宽松（容忍空白 / 大小写 / 尾部 '='），
 * decodeStrict 追加尾长与填充位校验（供 { strict: true } 使用）。
 */
import { OtpError, OtpErrorCode } from "../errors";

const BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

/**
 * 归一化：去空白 → 去尾部 '=' → 转大写。
 * decode 与 decodeStrict 必须共用本函数（同一表达式）：各自复制一份会让「规范形式」的判据漂移。
 */
export function normalize(input: string): string {
  return input.replace(/\s/g, "").replace(/=+$/, "").toUpperCase();
}

/**
 * RFC 4648 §6 解码：先归一化。
 * 空串抛 EMPTY_SECRET；非法字符抛 INVALID_BASE32_CHAR；解码长度 0 抛 SECRET_TOO_SHORT。
 * 实现：按 8 字符一组（组宽 5 字节）位拼接，缺位补 0，末组按剩余有效位截断。
 */
export function decode(input: string): Uint8Array {
  const normalized = normalize(input);

  if (normalized.length === 0) {
    throw new OtpError(OtpErrorCode.EMPTY_SECRET, "EMPTY_SECRET");
  }

  for (let i = 0; i < normalized.length; i++) {
    if (BASE32_ALPHABET.indexOf(normalized.charAt(i)) === -1) {
      throw new OtpError(
        OtpErrorCode.INVALID_BASE32_CHAR,
        "INVALID_BASE32_CHAR",
      );
    }
  }

  const length = Math.floor((normalized.length * 5) / 8);
  if (length === 0) {
    throw new OtpError(OtpErrorCode.SECRET_TOO_SHORT, "SECRET_TOO_SHORT");
  }

  const result = new Uint8Array(length);
  let outIndex = 0;

  for (let start = 0; start < normalized.length; start += 8) {
    const end = Math.min(start + 8, normalized.length);
    const groupLength = end - start;

    const buf: number[] = [];
    for (let i = start; i < end; i++) {
      buf.push(BASE32_ALPHABET.indexOf(normalized.charAt(i)));
    }
    for (let i = 0; i < 8 - groupLength; i++) {
      buf.push(0);
    }

    const bytesInGroup = Math.floor((groupLength * 5) / 8);

    // RFC 4648 位拼接；每字节 & 0xff 收敛为无符号字节。
    if (bytesInGroup >= 1) {
      result[outIndex] = ((buf[0] << 3) | (buf[1] >> 2)) & 0xff;
    }
    if (bytesInGroup >= 2) {
      result[outIndex + 1] =
        ((buf[1] << 6) | (buf[2] << 1) | (buf[3] >> 4)) & 0xff;
    }
    if (bytesInGroup >= 3) {
      result[outIndex + 2] = ((buf[3] << 4) | (buf[4] >> 1)) & 0xff;
    }
    if (bytesInGroup >= 4) {
      result[outIndex + 3] =
        ((buf[4] << 7) | (buf[5] << 2) | (buf[6] >> 3)) & 0xff;
    }
    if (bytesInGroup >= 5) {
      result[outIndex + 4] = ((buf[6] << 5) | buf[7]) & 0xff;
    }
    outIndex += bytesInGroup;
  }

  return result;
}

/**
 * RFC 4648 §6 编码（大写、无填充）。输出字符数 = ceil(len*8/5)；空数组返回空串（不抛错，语义由调用方定）。
 * 实现：8 位进 / 5 位出的位缓冲拼接，不经过逐字符二进制字符串。
 */
export function encode(bytes: Uint8Array): string {
  if (bytes.length === 0) {
    return "";
  }

  const parts: string[] = [];
  let buffer = 0;
  let bitsLeft = 0;
  for (let i = 0; i < bytes.length; i++) {
    buffer = (buffer << 8) | bytes[i];
    bitsLeft += 8;
    while (bitsLeft >= 5) {
      parts.push(BASE32_ALPHABET.charAt((buffer >>> (bitsLeft - 5)) & 31));
      bitsLeft -= 5;
    }
  }
  // 末组余量左移补 0（无填充）。
  if (bitsLeft > 0) {
    parts.push(BASE32_ALPHABET.charAt((buffer << (5 - bitsLeft)) & 31));
  }
  return parts.join("");
}

/**
 * 严格解码：归一化后必须是「解码再编码可无损还原」的规范形式。
 *
 * 为什么这样判定：RFC 4648 §6 以 8 字符（40 bit = 5 字节）为单位，合法尾长只有 {0,2,4,5,7}；
 * 尾长 ∈ {1,3,6} 对应「不足整字节的非零余量」或「多出 1 bit」，decode 会静默丢弃这些位。
 * 尾长合法时，末字符的低位填充位必须为 0 —— 等价于 encode(decode(s)) === s（decode 对缺位补 0），
 * 所以用一次再编码比对即可覆盖两种失真，无需维护逐尾长的掩码表。
 *
 * 归一化本身（大小写 / 空白 / 尾部 '='）仍被容忍：strict 拒绝的是「规范 base32 不可能产生」的文本，
 * 而不是大小写风格。错误码优先级与 decode 一致：空 → EMPTY_SECRET，非法字符 → INVALID_BASE32_CHAR
 * （先于尾长判定，让「有错别字」优先暴露），再到 INVALID_BASE32_PADDING。
 */
export function decodeStrict(input: string): Uint8Array {
  const normalized = normalize(input);

  if (normalized.length === 0) {
    throw new OtpError(OtpErrorCode.EMPTY_SECRET, "EMPTY_SECRET");
  }

  for (let i = 0; i < normalized.length; i++) {
    if (BASE32_ALPHABET.indexOf(normalized.charAt(i)) === -1) {
      throw new OtpError(
        OtpErrorCode.INVALID_BASE32_CHAR,
        "INVALID_BASE32_CHAR",
      );
    }
  }

  const tail = normalized.length % 8;
  if (tail === 1 || tail === 3 || tail === 6) {
    throw new OtpError(
      OtpErrorCode.INVALID_BASE32_PADDING,
      "INVALID_BASE32_PADDING",
    );
  }

  // 已归一化，decode 内部的 normalize 是幂等的；单字符长度已在上面先抛 PADDING，不会落到 SECRET_TOO_SHORT。
  const bytes = decode(normalized);
  if (encode(bytes) !== normalized) {
    throw new OtpError(
      OtpErrorCode.INVALID_BASE32_PADDING,
      "INVALID_BASE32_PADDING",
    );
  }
  return bytes;
}
