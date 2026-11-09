/**
 * 共享测试向量断言（规范 §11.2）：15 组 keyB64 / ciphertextB64 / tagB64 / kcvB64 + 解密回环。
 * oracle = docs/specs/mfa-backup-v1.vectors.json（由 node:crypto 生成，与两端实现无关）。
 */
import { describe, expect, it } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import { aesGcmDecrypt, aesGcmEncrypt } from "../../src/backup/aes-gcm";
import { decodeBase64Strict, encodeBase64 } from "../../src/backup/base64";
import {
  computeKcv,
  normalizePassword,
  utf8ToBytes,
} from "../../src/backup/crypto";
import { buildAad, type EnvelopeMeta } from "../../src/backup/envelope";
import type { BackupItem } from "../../src/backup/payload";
import { pbkdf2Sha256 } from "../../src/backup/pbkdf2";
import {
  AAD_PREFIX,
  KCV_LABEL,
  KEY_BYTES,
  METHOD,
  VERSION,
} from "../../src/backup/spec";

interface VectorCase {
  id: string;
  note: string;
  passwordRaw: string;
  passwordNormalized: string;
  iterations: number;
  meta: EnvelopeMeta;
  aad: string;
  saltB64: string;
  ivB64: string;
  keyB64: string;
  payloadJson: string;
  plaintextB64?: string;
  ciphertextB64: string;
  tagB64: string;
  kcvB64: string;
}

interface VectorFile {
  aadPrefix: string;
  kcvLabel: string;
  exampleEnvelope: {
    format: string;
    version: number;
    method: string;
    key: {
      iterations: number;
      salt: string;
      iv: string;
      tag: string;
      kcv: string;
    };
    data: string;
    meta: { count: number; createdAt: string; source: string; app: string };
  };
  cases: VectorCase[];
}

const VECTORS: VectorFile = JSON.parse(
  fs.readFileSync(
    path.resolve(
      import.meta.dir,
      "../../../../../docs/specs/mfa-backup-v1.vectors.json",
    ),
    "utf8",
  ),
) as VectorFile;

const plaintextOf = (c: VectorCase): Uint8Array => {
  return c.plaintextB64 === undefined
    ? utf8ToBytes(c.payloadJson)
    : decodeBase64Strict(c.plaintextB64);
};

describe("backup vectors", () => {
  it("spec_aadAndKcvLabelMatch", () => {
    expect(VECTORS.aadPrefix).toBe(AAD_PREFIX);
    expect(VECTORS.kcvLabel).toBe(KCV_LABEL);
    expect(VECTORS.cases.length).toBe(15);
  });

  // AAD 现在含 meta（规范 §4.2）：生成器与实现必须拼出逐字节相同的串
  it("cases_aadMatchesCanonicalMeta", () => {
    for (const c of VECTORS.cases) {
      expect(c.aad).toBe(buildAad(VERSION, METHOD, c.meta));
      expect(c.aad.startsWith(VECTORS.aadPrefix)).toBe(true);
    }
  });

  it("cases_areUnique", () => {
    const ids = VECTORS.cases.map((c) => c.id);

    expect(new Set(ids).size).toBe(ids.length);
  });

  for (const c of VECTORS.cases) {
    it(`${c.id}_keyMatches`, () => {
      const password = utf8ToBytes(normalizePassword(c.passwordRaw));

      expect(normalizePassword(c.passwordRaw)).toBe(c.passwordNormalized);

      const key = pbkdf2Sha256(
        password,
        decodeBase64Strict(c.saltB64),
        c.iterations,
        KEY_BYTES,
      );

      expect(encodeBase64(key)).toBe(c.keyB64);
    });

    it(`${c.id}_ciphertextAndTagMatch`, () => {
      const key = decodeBase64Strict(c.keyB64);
      const result = aesGcmEncrypt(
        key,
        decodeBase64Strict(c.ivB64),
        utf8ToBytes(c.aad),
        plaintextOf(c),
      );

      expect(encodeBase64(result.ciphertext)).toBe(c.ciphertextB64);
      expect(encodeBase64(result.tag)).toBe(c.tagB64);
    });

    it(`${c.id}_kcvMatches`, () => {
      const kcv = computeKcv(decodeBase64Strict(c.keyB64));

      expect(encodeBase64(kcv)).toBe(c.kcvB64);
    });

    it(`${c.id}_decryptRoundTrip`, () => {
      const plaintext = aesGcmDecrypt(
        decodeBase64Strict(c.keyB64),
        decodeBase64Strict(c.ivB64),
        utf8ToBytes(c.aad),
        decodeBase64Strict(c.ciphertextB64),
        decodeBase64Strict(c.tagB64),
      );

      expect(plaintext).not.toBeNull();
      expect(Array.from(plaintext ?? new Uint8Array())).toEqual(
        Array.from(plaintextOf(c)),
      );
    });
  }

  it("exampleEnvelope_matchesCase12", () => {
    const c = VECTORS.cases.find((item) => item.id === "case-12");

    expect(c).toBeDefined();

    if (c === undefined) {
      return;
    }

    expect(VECTORS.exampleEnvelope.key.iterations).toBe(c.iterations);
    expect(VECTORS.exampleEnvelope.key.salt).toBe(c.saltB64);
    expect(VECTORS.exampleEnvelope.key.iv).toBe(c.ivB64);
    expect(VECTORS.exampleEnvelope.key.tag).toBe(c.tagB64);
    expect(VECTORS.exampleEnvelope.key.kcv).toBe(c.kcvB64);
    expect(VECTORS.exampleEnvelope.data).toBe(c.ciphertextB64);
    expect(VECTORS.exampleEnvelope.meta).toEqual(c.meta);
    expect(VECTORS.exampleEnvelope.meta.count).toBe(
      (JSON.parse(c.payloadJson) as { items: BackupItem[] }).items.length,
    );
  });
});
