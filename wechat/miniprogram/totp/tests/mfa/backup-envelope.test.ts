/**
 * 信封结构校验测试（规范 §3.1 / §7 / §8 判定顺序）。
 */
import { describe, expect, it } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import { decodeBase64Strict, encodeBase64 } from "../../src/backup/base64";
import {
  canonicalMetaJson,
  type Envelope,
  parseEnvelope,
  stringifyEnvelope,
} from "../../src/backup/envelope";
import { BackupErrorCode } from "../../src/backup/spec";

const VECTORS = JSON.parse(
  fs.readFileSync(
    path.resolve(
      import.meta.dir,
      "../../../../../docs/specs/mfa-backup-v1.vectors.json",
    ),
    "utf8",
  ),
) as { exampleEnvelope: Envelope };

const EXAMPLE = VECTORS.exampleEnvelope;

const withEnvelope = (patch: Record<string, unknown>): string => {
  const base = JSON.parse(JSON.stringify(EXAMPLE)) as Record<string, unknown>;

  return JSON.stringify({ ...base, ...patch });
};

const expectCode = (text: string, code: BackupErrorCode): void => {
  const result = parseEnvelope(text);

  expect(result.ok).toBe(false);

  if (!result.ok) {
    expect(result.code).toBe(code);
  }
};

describe("backup envelope", () => {
  it("parse_exampleEnvelopeSucceeds", () => {
    const result = parseEnvelope(JSON.stringify(EXAMPLE));

    expect(result.ok).toBe(true);

    if (result.ok) {
      expect(result.envelope.key.iterations).toBe(10000);
      expect(result.envelope.meta.source).toBe("huawei");
    }
  });

  it("parse_ignoresSurroundingWhitespaceAndTrailingNewline", () => {
    const result = parseEnvelope(`\n  ${JSON.stringify(EXAMPLE)}\n`);

    expect(result.ok).toBe(true);
  });

  it("parse_ignoresUnknownFields", () => {
    const result = parseEnvelope(
      withEnvelope({ extra: { nested: true }, key: { ...EXAMPLE.key, x: 1 } }),
    );

    expect(result.ok).toBe(true);
  });

  it("stringify_roundTrips", () => {
    const text = stringifyEnvelope(EXAMPLE);

    expect(text.startsWith('{"format":"mfa","version":1,"method"')).toBe(true);
    expect(parseEnvelope(text).ok).toBe(true);
  });

  // meta 同时是 AAD 尾部（规范 §4.2）：序列化必须复用它，不能各写一份
  it("stringify_metaMatchesCanonicalMetaJson", () => {
    expect(stringifyEnvelope(EXAMPLE)).toContain(
      `"meta":${canonicalMetaJson(EXAMPLE.meta)}`,
    );
  });

  it("parse_base64WhitespaceIsRejected", () => {
    expectCode(
      withEnvelope({ key: { ...EXAMPLE.key, salt: `${EXAMPLE.key.salt} \n` } }),
      BackupErrorCode.E_STRUCTURE,
    );
  });

  it("parse_base64MissingPaddingIsRejected", () => {
    const salt = EXAMPLE.key.salt.replace(/=/g, "");

    expectCode(
      withEnvelope({ key: { ...EXAMPLE.key, salt } }),
      BackupErrorCode.E_STRUCTURE,
    );
  });

  it("parse_base64UrlAlphabetIsRejected", () => {
    const salt = `${EXAMPLE.key.salt.slice(0, -2)}-_`;

    expectCode(
      withEnvelope({ key: { ...EXAMPLE.key, salt } }),
      BackupErrorCode.E_STRUCTURE,
    );
  });

  it("decodeBase64_rejectsNonMultipleOfFour", () => {
    let thrown: unknown = null;

    try {
      decodeBase64Strict("AAA");
    } catch (e) {
      thrown = e;
    }

    expect((thrown as { code?: string } | null)?.code).toBe("E_STRUCTURE");
  });

  it("decodeBase64_roundTrips", () => {
    const bytes = new Uint8Array([0, 1, 2, 250, 255]);

    expect(encodeBase64(bytes)).toBe("AAEC+v8=");
    expect(Array.from(decodeBase64Strict("AAEC+v8="))).toEqual(
      Array.from(bytes),
    );
  });

  it("parse_nonJsonIsEFormat", () => {
    expectCode("not json", BackupErrorCode.E_FORMAT);
  });

  it("parse_wrongFormatIsEFormat", () => {
    expectCode(withEnvelope({ format: "otpauth" }), BackupErrorCode.E_FORMAT);
  });

  it("parse_version2IsEVersion", () => {
    expectCode(withEnvelope({ version: 2 }), BackupErrorCode.E_VERSION);
  });

  it("parse_versionNonIntegerOrBelowOneIsEStructure", () => {
    expectCode(withEnvelope({ version: 1.5 }), BackupErrorCode.E_STRUCTURE);
    expectCode(withEnvelope({ version: 0 }), BackupErrorCode.E_STRUCTURE);
    expectCode(withEnvelope({ version: "1" }), BackupErrorCode.E_STRUCTURE);
  });

  it("parse_unknownMethodIsEMethod", () => {
    expectCode(
      withEnvelope({ method: "PBKDF2-SHA256/AES-256-CBC" }),
      BackupErrorCode.E_METHOD,
    );
  });

  it("parse_iterationsOutOfRangeIsEStructure", () => {
    expectCode(
      withEnvelope({ key: { ...EXAMPLE.key, iterations: 9999 } }),
      BackupErrorCode.E_STRUCTURE,
    );
    expectCode(
      withEnvelope({ key: { ...EXAMPLE.key, iterations: 500001 } }),
      BackupErrorCode.E_STRUCTURE,
    );
    expectCode(
      withEnvelope({ key: { ...EXAMPLE.key, iterations: 10000.5 } }),
      BackupErrorCode.E_STRUCTURE,
    );
  });

  it("parse_wrongKeyLengthsAreEStructure", () => {
    for (const field of ["salt", "iv", "tag", "kcv"] as const) {
      const original = EXAMPLE.key[field];
      const bytes = decodeBase64Strict(original);
      const broken = bytes.subarray(0, bytes.length - 1);

      expectCode(
        withEnvelope({
          key: { ...EXAMPLE.key, [field]: encodeBase64(broken) },
        }),
        BackupErrorCode.E_STRUCTURE,
      );
    }
  });

  it("parse_emptyDataIsEStructure", () => {
    expectCode(withEnvelope({ data: "" }), BackupErrorCode.E_STRUCTURE);
  });

  it("parse_metaCountOutOfRangeIsEStructure", () => {
    expectCode(
      withEnvelope({ meta: { ...EXAMPLE.meta, count: 501 } }),
      BackupErrorCode.E_STRUCTURE,
    );
    expectCode(
      withEnvelope({ meta: { ...EXAMPLE.meta, count: -1 } }),
      BackupErrorCode.E_STRUCTURE,
    );
  });

  it("parse_createdAtAcceptsZoneOffsets", () => {
    const accepted = [
      "2026-11-07T08:00:00.000+08:00",
      "2026-11-06T19:00:00.000-05:00",
      "2026-11-07T12:15:00.000+05:45",
      "2026-11-07T00:00:00.000+00:00",
      "2026-11-07T00:00:00.000Z",
      "2026-11-07T08:00:00.5+08:00",
      "2026-11-07T08:00:00+08:00",
    ];

    for (const createdAt of accepted) {
      const result = parseEnvelope(
        withEnvelope({ meta: { ...EXAMPLE.meta, createdAt } }),
      );

      expect(result.ok).toBe(true);
    }
  });

  it("parse_createdAtRejectsMalformedOrOutOfRange", () => {
    const rejected = [
      "2026-11-07T00:00:00+0800", // 偏移缺冒号
      "2026-11-07T00:00:00+24:00", // 偏移越界
      "2026-11-07T00:00:00+14:01", // 14 小时只允许 00 分
      "2026-11-07 00:00:00", // 本地时间无时区
      "2026-11-07T00:00:00", // 缺时区
      "2026-02-30T00:00:00.000Z", // 日历非法
      "2026-11-07T24:00:00.000Z", // 小时越界
      "1969-12-31T23:59:59.000Z", // 年份下限
    ];

    for (const createdAt of rejected) {
      expectCode(
        withEnvelope({ meta: { ...EXAMPLE.meta, createdAt } }),
        BackupErrorCode.E_STRUCTURE,
      );
    }
  });

  it("parse_sourceMustBeKnown", () => {
    expectCode(
      withEnvelope({ meta: { ...EXAMPLE.meta, source: "google" } }),
      BackupErrorCode.E_STRUCTURE,
    );
  });

  it("parse_appMustBePrintableAscii", () => {
    for (const app of ["版本1", 'a"b', "a\\b", "a\nb", "x".repeat(33)]) {
      expectCode(
        withEnvelope({ meta: { ...EXAMPLE.meta, app } }),
        BackupErrorCode.E_STRUCTURE,
      );
    }

    // 空格（0x20）属于可打印 ASCII，允许
    expect(
      parseEnvelope(
        withEnvelope({
          meta: { ...EXAMPLE.meta, app: "1.9.0 (release)" },
        }),
      ).ok,
    ).toBe(true);
  });
});
