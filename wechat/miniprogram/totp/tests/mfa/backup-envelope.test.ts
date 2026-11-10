/**
 * 备份信封预检测试：只覆盖“不花口令就能发现”的结构性与规模问题。
 * 预检接受任意来源，因此用例刻意使用无类型的原始对象。
 */
import { describe, expect, it } from "bun:test";
import {
  MAX_DATA_CHARS,
  MAX_ENVELOPE_TEXT_CHARS,
} from "../../src/constant/backup";
import {
  BackupParseError,
  BackupParseErrorCode,
  parseEnvelope,
  validateEnvelope,
} from "../../src/models/backup";

const rawEnvelope = (
  overrides: Record<string, unknown> = {},
): Record<string, unknown> => ({
  format: "application",
  kind: "totp",
  version: 1,
  meta: { created_at: "2026-06-28T14:30:00+08:00", count: 2 },
  kdf: { alg: "pbkdf2-sha256", iterations: 600000, salt: "c2FsdA==" },
  cipher: { alg: "aes-256-gcm", nonce: "bm9uY2U=" },
  data: "ZGF0YQ==",
  ...overrides,
});

/** 只改 meta 的某几个字段，保留合法默认值。 */
const withMeta = (
  patch: Record<string, unknown>,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> => {
  return rawEnvelope({
    meta: { created_at: "2026-06-28T14:30:00+08:00", count: 2, ...patch },
    ...overrides,
  });
};

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
    const envelope = rawEnvelope({ future: { note: "kept" } });

    // 未知字段必须原样保留，后端升级后前端不丢数据
    expect(validateEnvelope(envelope)).toBe(envelope);
  });

  it("accepts_zulu_and_fractional_seconds", () => {
    const envelope = withMeta({ created_at: "2026-06-28T06:30:00.5Z" });

    expect(validateEnvelope(envelope)).toBe(envelope);
  });

  it("keeps_prototype_chain_for_instanceof", () => {
    const e = new BackupParseError(
      BackupParseErrorCode.E_KIND,
      "备份类型不受支持（仅支持 TOTP）",
    );

    // 微信 ES5 降级后仍必须能通过 instanceof / name 判定（见 otp/errors.ts）
    expect(e).toBeInstanceOf(BackupParseError);
    expect(e).toBeInstanceOf(Error);
    expect(e.name).toBe("BackupParseError");
    expect(e.code).toBe("E_KIND");
  });

  it("rejects_structural_errors_with_explicit_codes", () => {
    const cases: Array<[string, unknown, BackupParseErrorCode]> = [
      ["整体为数组", [], BackupParseErrorCode.E_STRUCTURE],
      ["整体为 null", null, BackupParseErrorCode.E_STRUCTURE],
      [
        "format 缺失",
        rawEnvelope({ format: undefined }),
        BackupParseErrorCode.E_FORMAT,
      ],
      [
        "format 错误",
        rawEnvelope({ format: "mfa" }),
        BackupParseErrorCode.E_FORMAT,
      ],
      [
        "kind 错误",
        rawEnvelope({ kind: "password" }),
        BackupParseErrorCode.E_KIND,
      ],
      ["版本过高", rawEnvelope({ version: 2 }), BackupParseErrorCode.E_VERSION],
      [
        "版本非整数",
        rawEnvelope({ version: 1.5 }),
        BackupParseErrorCode.E_STRUCTURE,
      ],
      [
        "版本过低",
        rawEnvelope({ version: 0 }),
        BackupParseErrorCode.E_STRUCTURE,
      ],
      [
        "版本为字符串",
        rawEnvelope({ version: "1" }),
        BackupParseErrorCode.E_STRUCTURE,
      ],
      [
        "meta 缺失",
        rawEnvelope({ meta: undefined }),
        BackupParseErrorCode.E_STRUCTURE,
      ],
      [
        "meta 为数组",
        rawEnvelope({ meta: [] }),
        BackupParseErrorCode.E_STRUCTURE,
      ],
    ];

    for (const [name, value, code] of cases) {
      expect({ name, code: codeOf(() => validateEnvelope(value)) }).toEqual({
        name,
        code,
      });
    }
  });

  it("rejects_illegal_count", () => {
    for (const count of [0, -1, 1.5, "2"]) {
      expect(codeOf(() => validateEnvelope(withMeta({ count })))).toBe(
        BackupParseErrorCode.E_STRUCTURE,
      );
    }
  });

  it("rejects_count_over_server_limit", () => {
    expect(codeOf(() => validateEnvelope(withMeta({ count: 51 })))).toBe(
      BackupParseErrorCode.E_LIMIT,
    );
  });

  it("rejects_illegal_created_at", () => {
    for (const created_at of [
      "",
      "2026-06-28",
      "2026-02-30T00:00:00+08:00",
      "2026-06-28T14:30:00",
      1700000000,
    ]) {
      expect(codeOf(() => validateEnvelope(withMeta({ created_at })))).toBe(
        BackupParseErrorCode.E_STRUCTURE,
      );
    }
  });

  it("rejects_missing_or_malformed_crypto_fields", () => {
    const cases: Array<Record<string, unknown>> = [
      { kdf: undefined },
      { cipher: undefined },
      { kdf: [] },
      { cipher: "aes-256-gcm" },
    ];

    for (const overrides of cases) {
      expect(codeOf(() => validateEnvelope(rawEnvelope(overrides)))).toBe(
        BackupParseErrorCode.E_STRUCTURE,
      );
    }
  });

  it("rejects_empty_or_oversized_data", () => {
    for (const data of ["", 123, "A".repeat(MAX_DATA_CHARS + 1)]) {
      expect(codeOf(() => validateEnvelope(rawEnvelope({ data })))).toBe(
        BackupParseErrorCode.E_STRUCTURE,
      );
    }
  });

  it("rejects_oversized_text_before_parsing", () => {
    const text = "x".repeat(MAX_ENVELOPE_TEXT_CHARS + 1);

    expect(codeOf(() => parseEnvelope(text))).toBe(
      BackupParseErrorCode.E_LIMIT,
    );
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
    const envelope = rawEnvelope();

    expect(parseEnvelope(JSON.stringify(envelope)).meta.count).toBe(2);
  });
});
