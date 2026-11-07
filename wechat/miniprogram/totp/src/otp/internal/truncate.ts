/**
 * RFC 4226 §5.3 动态截断（纯函数，无平台依赖）。
 * 只做截断（屏蔽最高位，得 31 位非负整数）；取模只在 digits.format 完成。
 */
import { OtpError, OtpErrorCode } from "../errors";

export function apply(digest: Uint8Array): number {
  if (digest.length < 20) {
    throw new OtpError(OtpErrorCode.CRYPTO_FAILED, "CRYPTO_FAILED");
  }

  const offset = digest[digest.length - 1] & 0x0f;
  // & 0x7f 清掉最高位；末尾 >>> 0 转回无符号 32 位，保证结果为 31 位非负整数。
  const v =
    (((digest[offset] & 0x7f) << 24) |
      (digest[offset + 1] << 16) |
      (digest[offset + 2] << 8) |
      digest[offset + 3]) >>>
    0;
  return v;
}
