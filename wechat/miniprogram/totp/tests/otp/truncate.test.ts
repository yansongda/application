/**
 * RFC 4226 §5.3 动态截断：digest 末字节低 4 位为 offset，取 4 字节并清最高位。
 * 期望值由 A.2 的 digestHex 按 RFC 定义直接计算（非被测实现反推），并与 code 的取模关系对齐。
 */
import { describe, expect, it } from "bun:test";
import { apply } from "../../src/otp/internal/truncate";
import { expectCode } from "./helpers";
import { hexBytes, RFC4226_SHA1_6DIGIT } from "./vectors";

/** A.2 counter 0..9 的 31 位截断值（独立于实现，按 RFC 4226 §5.3 逐字节计算）。 */
const TRUNCATED_31BIT = [
  1284755224, 1094287082, 137359152, 1726969429, 1640338314, 868254676,
  1918287922, 82162583, 673399871, 645520489,
];

describe("truncate", () => {
  for (let i = 0; i < RFC4226_SHA1_6DIGIT.length; i++) {
    const v = RFC4226_SHA1_6DIGIT[i];
    it(`apply_counter_${v.counter}`, () => {
      const value = apply(hexBytes(v.digestHex));
      expect(value).toBe(TRUNCATED_31BIT[i]);
      // 与 A.2 code 的取模关系（唯一取模点不在 truncate，但这里锁定两者一致性）
      expect(value % 1000000).toBe(Number.parseInt(v.code, 10));
    });
  }

  it("apply_shortDigest_throwsCryptoFailed", () => {
    expectCode(() => apply(new Uint8Array(19)), "CRYPTO_FAILED");
  });

  it("apply_ignoresHighBitOfTruncatedWord", () => {
    // 末字节 offset=0；首字节 0xff → & 0x7f 后应得 0x7f000000（非负 31 位）
    const digest = new Uint8Array(20);
    digest[0] = 0xff;
    expect(apply(digest)).toBe(0x7f000000);
  });
});
