/**
 * 备份信封预检测试：只覆盖“不花口令就能发现”的结构性问题。
 */
import { describe, expect, it } from "bun:test";
import {
  parseEnvelope,
  validateEnvelope,
} from "../../src/models/backup/envelope";
import {
  BackupParseError,
  BackupParseErrorCode,
} from "../../src/models/backup/errors";
import type { BackupEnvelope } from "../../src/types/backup";

const validEnvelope = (
  overrides: Partial<BackupEnvelope> = {},
): BackupEnvelope => ({
  format: "application",
  kind: "totp",
  version: 1,
  meta: { created_at: "2026-06-28T14:30:00+08:00", count: 2 },
  kdf: { alg: "pbkdf2-sha256", iterations: 600000, salt: "c2FsdA==" },
  cipher: { alg: "aes-256-gcm", nonce: "bm9uY2U=" },
  data: "ZGF0YQ==",
  ...overrides,
});

const codeOf = (fn: () => unknown): BackupParseErrorCode => {
  try {
    fn();
  } catch (e: unknown) {
    if (e instanceof BackupParseError) {
      return e.code;
    }

    throw e;
  }

  throw new Error("expected BackupParseError");
};

describe("backup envelope", () => {
  it("accepts_valid_envelope_and_keeps_unknown_fields", () => {
    const envelope = validEnvelope({
      format: "application",
      // 未知字段必须原样保留，后端升级后前端不丢数据
      ...({ future: { note: "ignored" } } as Partial<BackupEnvelope>),
    });

    expect(validateEnvelope(envelope)).toBe(envelope);
  });

  it("rejects_wrong_format", () => {
    expect(
      codeOf(() => validateEnvelope(validEnvelope({ format: "mfa" }))),
    ).toBe(BackupParseErrorCode.E_FORMAT);
  });

  it("rejects_wrong_kind", () => {
    expect(
      codeOf(() => validateEnvelope(validEnvelope({ kind: "password" }))),
    ).toBe(BackupParseErrorCode.E_KIND);
  });

  it("rejects_newer_version", () => {
    expect(codeOf(() => validateEnvelope(validEnvelope({ version: 2 })))).toBe(
      BackupParseErrorCode.E_VERSION,
    );
  });

  it("rejects_non_integer_or_zero_version", () => {
    expect(
      codeOf(() => validateEnvelope(validEnvelope({ version: 1.5 }))),
    ).toBe(BackupParseErrorCode.E_STRUCTURE);
    expect(codeOf(() => validateEnvelope(validEnvelope({ version: 0 })))).toBe(
      BackupParseErrorCode.E_STRUCTURE,
    );
  });

  it("rejects_non_positive_count", () => {
    for (const count of [0, -1, 1.5]) {
      const envelope = validEnvelope({
        meta: { created_at: "2026-06-28T14:30:00+08:00", count },
      });

      expect(codeOf(() => validateEnvelope(envelope))).toBe(
        BackupParseErrorCode.E_STRUCTURE,
      );
    }
  });

  it("rejects_count_over_server_limit", () => {
    const envelope = validEnvelope({
      meta: { created_at: "2026-06-28T14:30:00+08:00", count: 51 },
    });

    expect(codeOf(() => validateEnvelope(envelope))).toBe(
      BackupParseErrorCode.E_LIMIT,
    );
  });

  it("rejects_illegal_created_at", () => {
    for (const created_at of [
      "",
      "2026-06-28",
      "2026-02-30T00:00:00+08:00",
      "2026-06-28T14:30:00",
    ]) {
      const envelope = validEnvelope({ meta: { created_at, count: 2 } });

      expect(codeOf(() => validateEnvelope(envelope))).toBe(
        BackupParseErrorCode.E_STRUCTURE,
      );
    }
  });

  it("accepts_zulu_and_fractional_seconds", () => {
    const envelope = validEnvelope({
      meta: { created_at: "2026-06-28T06:30:00.5Z", count: 2 },
    });

    expect(validateEnvelope(envelope)).toBe(envelope);
  });

  it("rejects_missing_crypto_fields_and_data", () => {
    expect(
      codeOf(() => validateEnvelope({ ...validEnvelope(), kdf: undefined })),
    ).toBe(BackupParseErrorCode.E_STRUCTURE);

    expect(
      codeOf(() => validateEnvelope({ ...validEnvelope(), cipher: undefined })),
    ).toBe(BackupParseErrorCode.E_STRUCTURE);

    expect(
      codeOf(() => validateEnvelope({ ...validEnvelope(), data: "" })),
    ).toBe(BackupParseErrorCode.E_STRUCTURE);
  });

  it("rejects_json_text_that_is_not_an_object", () => {
    expect(codeOf(() => parseEnvelope("[]"))).toBe(
      BackupParseErrorCode.E_STRUCTURE,
    );
  });

  it("rejects_invalid_json_text", () => {
    expect(codeOf(() => parseEnvelope("not-json"))).toBe(
      BackupParseErrorCode.E_JSON,
    );
  });

  it("parses_valid_text", () => {
    const text = JSON.stringify(validEnvelope());

    expect(parseEnvelope(text).meta.count).toBe(2);
  });
});
