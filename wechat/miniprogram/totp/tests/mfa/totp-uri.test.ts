/**
 * otpauth URI 包装层契约测试（自设计文档 §3.3.1 / §3.9）。
 */
import { describe, expect, it } from "bun:test";
import { OtpError, OtpErrorCode, OtpType } from "@yansongda/miniprogram-otp";
import {
  buildTotpUri,
  describeOtpError,
  parseTotpUri,
  rebuildTotpUri,
} from "../../src/utils/totp-uri";

const CANONICAL = "JBSWY3DPEHPK3PXP";

// 期望抛出指定错误码（断言 code 比消息匹配更精确）
const expectCode = (fn: () => unknown, code: string): void => {
  let thrown: unknown = null;

  try {
    fn();
  } catch (e) {
    thrown = e;
  }

  expect(thrown instanceof OtpError).toBe(true);
  expect((thrown as OtpError).code).toBe(code);
};

describe("totp-uri", () => {
  it("parse_canonicalTotpPasses", () => {
    const p = parseTotpUri(
      `otpauth://totp/ACME%20Co:alice@example.com?secret=${CANONICAL}&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60`,
    );

    expect(p.type).toBe(OtpType.TOTP);
    expect(p.secret).toBe(CANONICAL);
    expect(p.issuer).toBe("ACME Co");
    expect(p.account).toBe("alice@example.com");
    expect(p.algorithm).toBe("SHA256");
    expect(p.digits).toBe(8);
    expect(p.period).toBe(60);
  });

  it("parse_strictRejectsTruncatedSecrets", () => {
    for (const bad of ["GGG", "MZXW6YT"]) {
      expectCode(
        () => parseTotpUri(`otpauth://totp/alice?secret=${bad}`),
        OtpErrorCode.INVALID_BASE32_PADDING,
      );
    }
  });

  it("parse_rejectsHotp", () => {
    expectCode(
      () =>
        parseTotpUri(
          `otpauth://hotp/ACME%20Co:alice?secret=${CANONICAL}&counter=42`,
        ),
      OtpErrorCode.UNSUPPORTED_OTPAUTH_TYPE,
    );
  });

  it("parse_rejectsNonTotpType", () => {
    expectCode(
      () => parseTotpUri(`otpauth://steam/alice?secret=${CANONICAL}`),
      OtpErrorCode.UNSUPPORTED_OTPAUTH_TYPE,
    );
  });

  it("rebuild_normalizesSchemeToLowercase", () => {
    const p = parseTotpUri(`OTPAUTH://TOTP/alice?secret=${CANONICAL}`);
    const uri = rebuildTotpUri(p);

    expect(uri).toBe(`otpauth://totp/alice?secret=${CANONICAL}&algorithm=SHA1`);
    expect(uri.startsWith("otpauth://totp/")).toBe(true);
  });

  it("rebuild_rejectsHotp", () => {
    expectCode(
      () =>
        rebuildTotpUri({
          type: OtpType.HOTP,
          secret: CANONICAL,
          algorithm: "SHA1",
          digits: 6,
          counter: 1,
          account: "alice",
        }),
      OtpErrorCode.UNSUPPORTED_OTPAUTH_TYPE,
    );
  });

  it("build_outputsCanonicalTotpUri", () => {
    const uri = buildTotpUri({
      issuer: "ACME",
      account: "alice",
      secret: CANONICAL,
      period: 30,
      digits: 6,
      algorithm: "SHA1",
    });

    expect(uri).toBe(
      `otpauth://totp/ACME:alice?secret=${CANONICAL}&issuer=ACME&algorithm=SHA1`,
    );
    expect(uri.startsWith("otpauth://totp/")).toBe(true);
  });

  it("build_emitsNonDefaults", () => {
    const uri = buildTotpUri({
      issuer: "ACME",
      account: "alice",
      secret: "jbsWy3DpeHPK3pXp",
      period: 60,
      digits: 8,
      algorithm: "SHA512",
    });

    expect(uri).toBe(
      `otpauth://totp/ACME:alice?secret=${CANONICAL}&issuer=ACME&algorithm=SHA512&digits=8&period=60`,
    );
  });

  it("build_normalizesLowercaseSecret", () => {
    const uri = buildTotpUri({
      issuer: "",
      account: "alice",
      secret: "jbsWy3DpeHPK3pXp",
      period: 30,
      digits: 6,
      algorithm: "SHA1",
    });

    expect(uri).toBe(`otpauth://totp/alice?secret=${CANONICAL}&algorithm=SHA1`);
  });

  it("build_rejectsInvalidSecret", () => {
    expectCode(
      () =>
        buildTotpUri({
          issuer: "ACME",
          account: "alice",
          secret: "GGG",
          period: 30,
          digits: 6,
          algorithm: "SHA1",
        }),
      OtpErrorCode.INVALID_BASE32_PADDING,
    );
  });

  it("build_rejectsEmptyAccount", () => {
    // v2 起 account 必填：创建页在调用前已本地拦截，此处钉住库侧契约
    expectCode(
      () =>
        buildTotpUri({
          issuer: "",
          account: "",
          secret: CANONICAL,
          period: 30,
          digits: 6,
          algorithm: "SHA1",
        }),
      OtpErrorCode.INVALID_OTPAUTH_URI,
    );
  });

  it("build_rejectsAccountWithColon", () => {
    expectCode(
      () =>
        buildTotpUri({
          issuer: "ACME",
          account: "a:b",
          secret: CANONICAL,
          period: 30,
          digits: 6,
          algorithm: "SHA1",
        }),
      OtpErrorCode.INVALID_OTPAUTH_URI,
    );
  });

  it("parse_rejectsMissingAccount", () => {
    // 1.x 可能产出的无 account URI（如旧二维码）在 v2 一律拒收
    expectCode(
      () => parseTotpUri(`otpauth://totp/?secret=${CANONICAL}`),
      OtpErrorCode.INVALID_OTPAUTH_URI,
    );
  });

  it("describeOtpError_mapsBase32Codes", () => {
    const expected = "密钥不符合 Base32 规范，请重新输入或扫码";

    for (const code of [
      OtpErrorCode.INVALID_BASE32_CHAR,
      OtpErrorCode.INVALID_BASE32_PADDING,
      OtpErrorCode.EMPTY_SECRET,
      OtpErrorCode.SECRET_TOO_SHORT,
    ]) {
      expect(describeOtpError(new OtpError(code, code))).toBe(expected);
    }
  });

  it("describeOtpError_mapsSecretContainerCode", () => {
    // 入参非字符串的防御分支：微信侧不可达，但文案口径与 Base32 类错误保持一致
    expect(
      describeOtpError(
        new OtpError(OtpErrorCode.INVALID_SECRET_CONTAINER, "x"),
      ),
    ).toBe("密钥不符合 Base32 规范，请重新输入或扫码");
  });

  it("describeOtpError_mapsTypeCode", () => {
    expect(
      describeOtpError(
        new OtpError(OtpErrorCode.UNSUPPORTED_OTPAUTH_TYPE, "x"),
      ),
    ).toBe("仅支持 TOTP 二维码");
  });

  it("describeOtpError_mapsConfigCodes", () => {
    const expected = "配置信息不合法";

    for (const code of [
      OtpErrorCode.INVALID_ALGORITHM,
      OtpErrorCode.INVALID_DIGITS,
      OtpErrorCode.INVALID_PERIOD,
    ]) {
      expect(describeOtpError(new OtpError(code, code))).toBe(expected);
    }
  });

  it("describeOtpError_mapsUriCode", () => {
    expect(
      describeOtpError(new OtpError(OtpErrorCode.INVALID_OTPAUTH_URI, "x")),
    ).toBe("二维码不是有效的 otpauth 链接");
  });

  it("describeOtpError_fallsBackForUnknown", () => {
    expect(
      describeOtpError(new OtpError(OtpErrorCode.CRYPTO_FAILED, "x")),
    ).toBe("操作失败，请重试");
    expect(describeOtpError(new Error("boom"))).toBe("操作失败，请重试");
    expect(describeOtpError("not an error")).toBe("操作失败，请重试");
  });

  it("describeOtpError_covers_every_known_code", () => {
    for (const code of Object.values(OtpErrorCode)) {
      expect(describeOtpError(new OtpError(code, code)).length).toBeGreaterThan(
        0,
      );
    }
  });

  it("describeOtpError_fallsBackForFutureCode", () => {
    expect(
      describeOtpError(new OtpError("FUTURE_CODE" as OtpErrorCode, "x")),
    ).toBe("操作失败，请重试");
  });
});
