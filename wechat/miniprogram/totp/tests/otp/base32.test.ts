/**
 * RFC 4648 §6 base32 编解码测试（宽松 / 严格两种语义）。
 */
import { describe, expect, it } from "bun:test";
import {
  decode,
  decodeStrict,
  encode,
  normalize,
} from "../../src/otp/internal/base32";
import { expectCode } from "./helpers";
import { asciiBytes, bytesEqual, RFC4648_BASE32 } from "./vectors";

describe("base32", () => {
  it("decodeRfcSecret_20Bytes", () => {
    const bytes = decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ");
    expect(bytes.length).toBe(20);
    expect(bytes[0]).toBe(49);
    expect(bytes[19]).toBe(48);
  });

  it("decodeTailGroupTruncate_MY", () => {
    const bytes = decode("MY");
    expect(bytes.length).toBe(1);
    expect(bytes[0]).toBe(0x66);
  });

  it("decodeCaseInsensitiveAndPaddingEquivalent", () => {
    const reference = decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ");
    expect(
      bytesEqual(decode("gezdgnbvgy3tqojqgezdgnbvgy3tqojq"), reference),
    ).toBe(true);
    expect(
      bytesEqual(decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ======"), reference),
    ).toBe(true);
  });

  it("decodeLeadingAndInternalWhitespace", () => {
    const reference = decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ");
    const messy = decode("  \tGEZD GNBV\nGY3T\rQOJQ GEZDGNBV GY3TQOJQ  ");
    expect(bytesEqual(messy, reference)).toBe(true);
  });

  it("decodeMultiplePaddingAmounts", () => {
    const reference = decode("GEZDGNBVGY3TQOJQ");
    expect(bytesEqual(decode("GEZDGNBVGY3TQOJQ="), reference)).toBe(true);
    expect(bytesEqual(decode("GEZDGNBVGY3TQOJQ===="), reference)).toBe(true);
    expect(bytesEqual(decode("GEZDGNBVGY3TQOJQ======"), reference)).toBe(true);
    expect(bytesEqual(decode("GEZDGNBVGY3TQOJQ========"), reference)).toBe(
      true,
    );
  });

  it("decodeBoundaryLengths_1to64Bytes", () => {
    for (let n = 1; n <= 64; n++) {
      const arr = new Uint8Array(n);
      for (let i = 0; i < n; i++) {
        arr[i] = (i * 91 + 17) & 0xff;
      }
      const encoded = encode(arr);
      const decoded = decode(encoded);
      expect(decoded.length).toBe(n);
      expect(bytesEqual(decoded, arr)).toBe(true);
    }
  });

  it("decodeEmptyThrowsEmptySecret", () => {
    expectCode(() => decode(""), "EMPTY_SECRET");
    expectCode(() => decode("   "), "EMPTY_SECRET");
    expectCode(() => decode("===="), "EMPTY_SECRET");
  });

  it("decodeSingleCharThrowsTooShort", () => {
    expectCode(() => decode("A"), "SECRET_TOO_SHORT");
  });

  it("decodeIllegalChars", () => {
    expectCode(() => decode("AB1"), "INVALID_BASE32_CHAR");
    expectCode(() => decode("ab0"), "INVALID_BASE32_CHAR");
  });

  it("decodeStrict_rfc4648VectorsRoundTrip", () => {
    for (const v of RFC4648_BASE32) {
      const canonical = normalize(v.base32Padded);
      if (canonical === "") {
        continue; // 空串另有 EMPTY_SECRET 用例
      }
      const bytes = decodeStrict(canonical);
      expect(bytesEqual(bytes, asciiBytes(v.plain))).toBe(true);
      expect(encode(bytes)).toBe(canonical);
    }
  });

  it("decodeStrict_acceptsLenientNormalization", () => {
    const reference = decodeStrict("MY");
    expect(bytesEqual(decodeStrict("MY======"), reference)).toBe(true);
    expect(bytesEqual(decodeStrict("  my \n"), reference)).toBe(true);
    expect(bytesEqual(decodeStrict("My"), reference)).toBe(true);
    expect(reference[0]).toBe(0x66);
  });

  it("decodeStrict_rejectsNonZeroTailBits", () => {
    // 末字符低位填充位被翻为非 0（尾长合法但填充位非法）
    expectCode(() => decodeStrict("MB"), "INVALID_BASE32_PADDING");
    expectCode(() => decodeStrict("MZXR"), "INVALID_BASE32_PADDING");
    expectCode(() => decodeStrict("MZXW7"), "INVALID_BASE32_PADDING");
    expectCode(() => decodeStrict("MZXW6YT"), "INVALID_BASE32_PADDING");
    expectCode(() => decodeStrict("MZXW6YTBOJ"), "INVALID_BASE32_PADDING");
  });

  it("decodeStrict_rejectsImpossibleTailLength", () => {
    expectCode(() => decodeStrict("A"), "INVALID_BASE32_PADDING");
    expectCode(() => decodeStrict("AAA"), "INVALID_BASE32_PADDING");
    expectCode(() => decodeStrict("MZXW6Y"), "INVALID_BASE32_PADDING");
  });

  it("decodeStrict_charErrorBeforeTailLength", () => {
    expectCode(() => decodeStrict("AB1"), "INVALID_BASE32_CHAR");
  });

  it("decodeStrict_emptyThrowsEmptySecret", () => {
    expectCode(() => decodeStrict(""), "EMPTY_SECRET");
    expectCode(() => decodeStrict("   "), "EMPTY_SECRET");
    expectCode(() => decodeStrict("===="), "EMPTY_SECRET");
  });

  it("decodeStrict_differsFromLenientOnSingleChar", () => {
    expectCode(() => decode("A"), "SECRET_TOO_SHORT");
    expectCode(() => decodeStrict("A"), "INVALID_BASE32_PADDING");
  });

  it("encodeDecodeRoundTrip_Seeds", () => {
    const sha1Seed = asciiBytes("12345678901234567890");
    const sha256Seed = asciiBytes("12345678901234567890123456789012");
    const sha512Seed = asciiBytes(
      "1234567890123456789012345678901234567890123456789012345678901234",
    );
    expect(encode(sha1Seed)).toBe("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ");
    expect(encode(sha256Seed)).toBe(
      "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA",
    );
    expect(encode(sha512Seed)).toBe(
      "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" +
        "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA",
    );
    expect(bytesEqual(decode(encode(sha512Seed)), sha512Seed)).toBe(true);
  });

  it("encodeEmptyReturnsEmptyString", () => {
    expect(encode(new Uint8Array(0))).toBe("");
  });

  it("encodeUppercaseNoPaddingAndLengthFormula", () => {
    const encoded = encode(asciiBytes("12345678901234567890"));
    expect(encoded === encoded.toUpperCase()).toBe(true);
    expect(encoded.indexOf("=")).toBe(-1);
    expect(encoded.length).toBe(32);
  });
});
