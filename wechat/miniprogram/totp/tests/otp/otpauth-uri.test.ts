/**
 * otpauth:// URI 解析 / 生成 / round-trip 测试（Google Authenticator Key URI Format）。
 */
import { describe, expect, it } from "bun:test";
import { OtpAlgorithm, OtpType } from "../../src/otp/options";
import { OTPAuthURI } from "../../src/otp/otpauth-uri";
import { expectCode } from "./helpers";

describe("otpauth-uri", () => {
  it("parse_standardTotpAllFields", () => {
    const p = OTPAuthURI.parse(
      "otpauth://totp/ACME%20Co:john@example.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60",
    );
    expect(p.type).toBe(OtpType.TOTP);
    expect(p.secret).toBe("JBSWY3DPEHPK3PXP");
    expect(p.algorithm).toBe(OtpAlgorithm.SHA256);
    expect(p.digits).toBe(8);
    expect(p.period).toBe(60);
    expect(p.issuer).toBe("ACME Co");
    expect(p.account).toBe("john@example.com");
  });

  it("parse_labelPercent3ASeparator", () => {
    const p = OTPAuthURI.parse(
      "otpauth://totp/ACME%3Aco@example.com?secret=JBSWY3DPEHPK3PXP",
    );
    expect(p.issuer).toBe("ACME");
    expect(p.account).toBe("co@example.com");
  });

  it("parse_missingOptionalDefaults", () => {
    const p = OTPAuthURI.parse("otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP");
    expect(p.algorithm).toBe(OtpAlgorithm.SHA1);
    expect(p.digits).toBe(6);
    expect(p.period).toBe(30);
    expect(p.account).toBe("alice");
  });

  it("parse_hotpWithCounter", () => {
    const p = OTPAuthURI.parse(
      "otpauth://hotp/ACME%20Co:alice?secret=JBSWY3DPEHPK3PXP&counter=42",
    );
    expect(p.type).toBe(OtpType.HOTP);
    expect(p.counter).toBe(42);
    expect(p.period).toBeUndefined();
  });

  it("parse_unknownParamsIgnored", () => {
    const p = OTPAuthURI.parse(
      "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&image=foo.png&lock=true",
    );
    expect(p.secret).toBe("JBSWY3DPEHPK3PXP");
    expect(p.digits).toBe(6);
  });

  it("parse_uppercaseScheme", () => {
    const p = OTPAuthURI.parse("OTPAUTH://TOTP/alice?secret=JBSWY3DPEHPK3PXP");
    expect(p.type).toBe(OtpType.TOTP);
    expect(p.secret).toBe("JBSWY3DPEHPK3PXP");
  });

  it("parse_queryIssuerWinsOverLabelPrefix", () => {
    const p = OTPAuthURI.parse(
      "otpauth://totp/Foo:bar?secret=JBSWY3DPEHPK3PXP&issuer=Baz",
    );
    expect(p.issuer).toBe("Baz");
    expect(p.account).toBe("bar");
  });

  it("parse_failInvalidScheme", () => {
    expectCode(
      () => OTPAuthURI.parse("http://example.com/x"),
      "INVALID_OTPAUTH_URI",
    );
  });

  it("parse_failUnsupportedType", () => {
    expectCode(
      () => OTPAuthURI.parse("otpauth://steam/alice?secret=JBSWY3DPEHPK3PXP"),
      "UNSUPPORTED_OTPAUTH_TYPE",
    );
  });

  it("parse_failMissingSecret", () => {
    expectCode(() => OTPAuthURI.parse("otpauth://totp/alice"), "EMPTY_SECRET");
  });

  it("parse_failInvalidAlgorithm", () => {
    expectCode(
      () =>
        OTPAuthURI.parse(
          "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&algorithm=MD5",
        ),
      "INVALID_ALGORITHM",
    );
  });

  it("parse_failInvalidDigits", () => {
    expectCode(
      () =>
        OTPAuthURI.parse(
          "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&digits=5",
        ),
      "INVALID_DIGITS",
    );
  });

  it("parse_failInvalidPeriod", () => {
    expectCode(
      () =>
        OTPAuthURI.parse(
          "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&period=0",
        ),
      "INVALID_PERIOD",
    );
  });

  it("parse_failInvalidCounter", () => {
    expectCode(
      () =>
        OTPAuthURI.parse(
          "otpauth://hotp/alice?secret=JBSWY3DPEHPK3PXP&counter=-1",
        ),
      "INVALID_COUNTER",
    );
  });

  it("parse_strictAcceptsCanonicalSecret", () => {
    const p = OTPAuthURI.parse(
      "otpauth://totp/alice?secret=jbswy3dpehpk3pxp&digits=8",
      { strict: true },
    );
    expect(p.secret).toBe("JBSWY3DPEHPK3PXP");
    expect(p.digits).toBe(8);
    expect(p.period).toBe(30);
  });

  it("parse_strictRejectsNonCanonicalSecret", () => {
    expectCode(
      () =>
        OTPAuthURI.parse("otpauth://totp/alice?secret=MZXW6YT", {
          strict: true,
        }),
      "INVALID_BASE32_PADDING",
    );
  });

  it("parse_defaultStaysLenientOnSameUri", () => {
    const p = OTPAuthURI.parse("otpauth://totp/alice?secret=MZXW6YT");
    expect(p.secret).toBe("MZXW6YQ");
  });

  it("parse_percentDecodeFailureFallsBackToRaw", () => {
    // '%ZZ' 无法百分号解码：回退原串，不应抛错
    const p = OTPAuthURI.parse(
      "otpauth://totp/alice%ZZ?secret=JBSWY3DPEHPK3PXP",
    );
    expect(p.account).toBe("alice%ZZ");
  });

  it("parse_percentEncodedColonAndSlash", () => {
    const p = OTPAuthURI.parse(
      "otpauth://totp/My%20Issuer%3Auser%2Fname?secret=JBSWY3DPEHPK3PXP",
    );
    expect(p.issuer).toBe("My Issuer");
    expect(p.account).toBe("user/name");
  });

  it("build_exactTotpFullOutput", () => {
    expect(
      OTPAuthURI.build({
        type: OtpType.TOTP,
        secret: "JBSWY3DPEHPK3PXP",
        algorithm: OtpAlgorithm.SHA256,
        digits: 8,
        period: 60,
        issuer: "ACME Co",
        account: "john@example.com",
      }),
    ).toBe(
      "otpauth://totp/ACME%20Co:john%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60",
    );
  });

  it("build_exactMinimalTotpOutput", () => {
    expect(
      OTPAuthURI.build({
        type: OtpType.TOTP,
        secret: "JBSWY3DPEHPK3PXP",
        algorithm: OtpAlgorithm.SHA1,
        digits: 6,
      }),
    ).toBe("otpauth://totp/?secret=JBSWY3DPEHPK3PXP&algorithm=SHA1");
  });

  it("build_exactHotpOutput", () => {
    expect(
      OTPAuthURI.build({
        type: OtpType.HOTP,
        secret: "JBSWY3DPEHPK3PXP",
        algorithm: OtpAlgorithm.SHA1,
        digits: 6,
        counter: 42,
        issuer: "ACME Co",
        account: "alice",
      }),
    ).toBe(
      "otpauth://hotp/ACME%20Co:alice?secret=JBSWY3DPEHPK3PXP&issuer=ACME%20Co&algorithm=SHA1&counter=42",
    );
  });

  it("build_normalizesSecret", () => {
    expect(
      OTPAuthURI.build({
        type: OtpType.TOTP,
        secret: "jbswy3dpeh pk3pxp=",
        algorithm: OtpAlgorithm.SHA1,
        digits: 6,
      }),
    ).toBe("otpauth://totp/?secret=JBSWY3DPEHPK3PXP&algorithm=SHA1");
  });

  it("build_invalidSecretChar_throws", () => {
    expectCode(
      () =>
        OTPAuthURI.build({
          type: OtpType.TOTP,
          secret: "JBSW!@#",
          algorithm: OtpAlgorithm.SHA1,
          digits: 6,
        }),
      "INVALID_BASE32_CHAR",
    );
  });

  it("roundtrip_totpFullFields", () => {
    const p = {
      type: OtpType.TOTP,
      secret: "JBSWY3DPEHPK3PXP",
      algorithm: OtpAlgorithm.SHA512,
      digits: 8,
      period: 60,
      issuer: "ACME Co",
      account: "john@example.com",
    } as const;
    const back = OTPAuthURI.parse(OTPAuthURI.build(p));
    expect(back.type).toBe(p.type);
    expect(back.secret).toBe(p.secret);
    expect(back.algorithm).toBe(p.algorithm);
    expect(back.digits).toBe(p.digits);
    expect(back.period).toBe(p.period);
    expect(back.issuer).toBe(p.issuer);
    expect(back.account).toBe(p.account);
  });

  it("roundtrip_hotp", () => {
    const p = {
      type: OtpType.HOTP,
      secret: "JBSWY3DPEHPK3PXP",
      algorithm: OtpAlgorithm.SHA1,
      digits: 6,
      counter: 42,
      issuer: "ACME Co",
      account: "alice",
    } as const;
    const back = OTPAuthURI.parse(OTPAuthURI.build(p));
    expect(back.type).toBe(p.type);
    expect(back.secret).toBe(p.secret);
    expect(back.counter).toBe(p.counter);
    expect(back.period).toBeUndefined();
  });

  it("roundtrip_minimalRequired", () => {
    const p = {
      type: OtpType.TOTP,
      secret: "JBSWY3DPEHPK3PXP",
      algorithm: OtpAlgorithm.SHA1,
      digits: 6,
    } as const;
    const back = OTPAuthURI.parse(OTPAuthURI.build(p));
    expect(back.period).toBe(30);
    expect(back.account).toBeUndefined();
    expect(back.issuer).toBeUndefined();
  });
});
