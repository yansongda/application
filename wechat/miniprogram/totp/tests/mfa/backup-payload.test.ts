/**
 * 明文 payload 校验测试（规范 §6）。
 */
import { describe, expect, it } from "bun:test";
import {
  type BackupItem,
  normalizeSecret,
  parsePayload,
  sanitizeItem,
  stringifyPayload,
} from "../../src/backup/payload";
import { BackupErrorCode } from "../../src/backup/spec";

const SECRET = "JBSWY3DPEHPK3PXP";

const ITEM: BackupItem = {
  issuer: "GitHub",
  username: "alice@example.com",
  secret: SECRET,
  period: 30,
  digits: 6,
  algorithm: "SHA1",
  tags: ["工作"],
  pinned: true,
};

describe("backup payload", () => {
  it("parse_validPayload", () => {
    const result = parsePayload(stringifyPayload([ITEM]));

    expect(result.ok).toBe(true);

    if (result.ok) {
      expect(result.items.length).toBe(1);
      expect(result.invalid.length).toBe(0);
      expect(result.items[0]).toEqual(ITEM);
    }
  });

  it("parse_emptyItemsIsAllowed", () => {
    const result = parsePayload('{"v":1,"items":[]}');

    expect(result.ok).toBe(true);

    if (result.ok) {
      expect(result.items.length).toBe(0);
    }
  });

  it("parse_wrongVersionIsEPayload", () => {
    const result = parsePayload('{"v":2,"items":[]}');

    expect(result.ok).toBe(false);

    if (!result.ok) {
      expect(result.code).toBe(BackupErrorCode.E_PAYLOAD);
    }
  });

  it("parse_tooManyItemsIsEPayload", () => {
    const items = Array.from({ length: 501 }, () => ITEM);
    const result = parsePayload(JSON.stringify({ v: 1, items }));

    expect(result.ok).toBe(false);
  });

  it("parse_invalidItemDoesNotBlockOthers", () => {
    const result = parsePayload(
      JSON.stringify({
        v: 1,
        items: [ITEM, { ...ITEM, secret: "JBSWY3DP1" }, ITEM],
      }),
    );

    expect(result.ok).toBe(true);

    if (result.ok) {
      expect(result.items.length).toBe(2);
      expect(result.invalid.length).toBe(1);
      expect(result.invalid[0].index).toBe(1);
    }
  });

  it("sanitize_fallsBackForDigitsAndAlgorithm", () => {
    const result = sanitizeItem({
      ...ITEM,
      digits: 9,
      algorithm: "MD5",
    });

    expect(result.ok).toBe(true);

    if (result.ok) {
      expect(result.item.digits).toBe(6);
      expect(result.item.algorithm).toBe("SHA1");
    }
  });

  it("sanitize_keepsSupportedDigitsAndAlgorithm", () => {
    const result = sanitizeItem({
      ...ITEM,
      digits: 8,
      algorithm: "sha256",
    });

    expect(result.ok).toBe(true);

    if (result.ok) {
      expect(result.item.digits).toBe(8);
      expect(result.item.algorithm).toBe("SHA256");
    }
  });

  it("sanitize_periodZeroIsInvalid", () => {
    const result = sanitizeItem({ ...ITEM, period: 0 });

    expect(result.ok).toBe(false);
  });

  it("sanitize_periodOverLimitIsInvalid", () => {
    const result = sanitizeItem({ ...ITEM, period: 86401 });

    expect(result.ok).toBe(false);
  });

  it("sanitize_issuerTooLongIsInvalid", () => {
    const result = sanitizeItem({ ...ITEM, issuer: "x".repeat(129) });

    expect(result.ok).toBe(false);
  });

  it("sanitize_truncatedSecretIsInvalid", () => {
    const result = sanitizeItem({ ...ITEM, secret: "JBSWY3DPEHPK3P" });

    expect(result.ok).toBe(false);

    if (!result.ok) {
      expect(result.reason).toContain("Base32");
    }
  });

  it("sanitize_dropsInvalidTagsAndKeepsOne", () => {
    const result = sanitizeItem({
      ...ITEM,
      tags: ["", "x".repeat(33), "工作", "备份"],
    });

    expect(result.ok).toBe(true);

    if (result.ok) {
      expect(result.item.tags).toEqual(["工作"]);
    }
  });

  it("sanitize_normalizesSecretCaseAndSpaces", () => {
    const result = sanitizeItem({
      ...ITEM,
      secret: "jbsw y3dp-ehpk3pxp",
    });

    expect(result.ok).toBe(true);

    if (result.ok) {
      expect(result.item.secret).toBe(SECRET);
    }
    expect(normalizeSecret("jbsw y3dp-ehpk3pxp=")).toBe(SECRET);
  });

  it("parse_emptyIssuerIsAllowed", () => {
    const result = sanitizeItem({ ...ITEM, issuer: "" });

    expect(result.ok).toBe(true);
  });

  it("parse_colonInIssuerAndUsernameIsAllowed", () => {
    expect(sanitizeItem({ ...ITEM, issuer: "A:B" }).ok).toBe(true);
    expect(sanitizeItem({ ...ITEM, username: "a:b" }).ok).toBe(true);
  });
});
