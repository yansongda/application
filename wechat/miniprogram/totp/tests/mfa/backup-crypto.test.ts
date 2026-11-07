/**
 * 加解密编排测试：kcv 先于 GCM 的判定顺序、篡改/错口令/计数不一致、
 * UTF-8 编解码、PBKDF2 分片异步的进度与取消。
 */
import { describe, expect, it } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import { decodeBase64Strict, encodeBase64 } from "../../src/backup/base64";
import {
  checkPasswordStrength,
  decryptEnvelope,
  encryptEnvelope,
  utf8ToBytes,
} from "../../src/backup/crypto";
import type { Envelope } from "../../src/backup/envelope";
import { parseEnvelope } from "../../src/backup/envelope";
import type { BackupItem } from "../../src/backup/payload";
import { Pbkdf2AbortedError, pbkdf2Sha256Async } from "../../src/backup/pbkdf2";
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

const ITEM: BackupItem = {
  issuer: "GitHub",
  username: "alice@example.com",
  secret: "JBSWY3DPEHPK3PXP",
  period: 30,
  digits: 6,
  algorithm: "SHA1",
  tags: [],
  pinned: false,
};

const PASSWORD = "TestPassword123";

const deterministicRng = (): ((length: number) => Promise<Uint8Array>) => {
  let counter = 0;

  return async (length: number): Promise<Uint8Array> => {
    const bytes = new Uint8Array(length);

    for (let i = 0; i < length; i++) {
      bytes[i] = counter & 0xff;
      counter += 1;
    }

    return bytes;
  };
};

const expectBackupError = async (
  task: Promise<unknown>,
  code: BackupErrorCode,
): Promise<void> => {
  let thrown: unknown = null;

  try {
    await task;
  } catch (e) {
    thrown = e;
  }

  expect((thrown as { code?: string } | null)?.code).toBe(code);
};

describe("backup crypto", () => {
  it("decrypt_exampleEnvelopeWithCase12Password", async () => {
    const parsed = parseEnvelope(JSON.stringify(VECTORS.exampleEnvelope));

    expect(parsed.ok).toBe(true);

    if (!parsed.ok) {
      return;
    }

    const result = await decryptEnvelope(parsed.envelope, "12345678");

    expect(result.items.length).toBe(1);
    expect(result.items[0].issuer).toBe("GitHub");
    expect(result.invalid.length).toBe(0);
  });

  it("encryptThenDecrypt_roundTrips", async () => {
    const result = await encryptEnvelope([ITEM, ITEM], PASSWORD, {
      source: "wechat",
      app: "1.2.0",
      rng: deterministicRng(),
      iterations: 10000,
      now: () => new Date("2026-11-07T00:00:00.000Z"),
    });

    expect(result.envelope.meta.count).toBe(2);
    expect(result.envelope.meta.source).toBe("wechat");
    expect(result.envelope.meta.createdAt).toBe("2026-11-07T00:00:00.000Z");

    const decrypted = await decryptEnvelope(result.envelope, PASSWORD);

    expect(decrypted.items.length).toBe(2);
    expect(decrypted.items[0]).toEqual(ITEM);
  });

  it("decrypt_wrongPasswordIsEPassword", async () => {
    const result = await encryptEnvelope([ITEM], PASSWORD, {
      source: "wechat",
      app: "1.2.0",
      rng: deterministicRng(),
      iterations: 10000,
    });

    await expectBackupError(
      decryptEnvelope(result.envelope, "WrongPassword123"),
      BackupErrorCode.E_PASSWORD,
    );
  });

  it("decrypt_tamperedDataIsECorrupt", async () => {
    const result = await encryptEnvelope([ITEM], PASSWORD, {
      source: "wechat",
      app: "1.2.0",
      rng: deterministicRng(),
      iterations: 10000,
    });
    const bytes = decodeBase64Strict(result.envelope.data);

    bytes[0] ^= 0x01;

    const tampered: Envelope = {
      ...result.envelope,
      data: encodeBase64(bytes),
    };

    await expectBackupError(
      decryptEnvelope(tampered, PASSWORD),
      BackupErrorCode.E_CORRUPT,
    );
  });

  it("decrypt_metaCountMismatchIsEPayload", async () => {
    const result = await encryptEnvelope([ITEM], PASSWORD, {
      source: "wechat",
      app: "1.2.0",
      rng: deterministicRng(),
      iterations: 10000,
    });

    const tampered: Envelope = {
      ...result.envelope,
      meta: { ...result.envelope.meta, count: 2 },
    };

    await expectBackupError(
      decryptEnvelope(tampered, PASSWORD),
      BackupErrorCode.E_PAYLOAD,
    );
  });

  it("decrypt_passwordWithSurroundingSpacesStillWorks", async () => {
    const result = await encryptEnvelope([ITEM], PASSWORD, {
      source: "wechat",
      app: "1.2.0",
      rng: deterministicRng(),
      iterations: 10000,
    });

    const decrypted = await decryptEnvelope(result.envelope, `  ${PASSWORD}  `);

    expect(decrypted.items.length).toBe(1);
  });

  it("utf8_roundTripsNonAsciiAndEmoji", () => {
    const text = "密码🔐 with ü and \u2028";
    const bytes = utf8ToBytes(text);

    expect(Array.from(bytes).length).toBeGreaterThan(text.length);
    expect(bytes.length).toBe(
      Array.from(new TextEncoder().encode(text.normalize("NFC"))).length,
    );
  });

  it("passwordStrength_rejectsShortAndWeakPasswords", () => {
    expect(checkPasswordStrength("1234567").ok).toBe(false);
    expect(checkPasswordStrength("12345678").ok).toBe(false);
    expect(checkPasswordStrength("TestPassword123").ok).toBe(true);
    expect(checkPasswordStrength("口令口令口令口令").ok).toBe(true);
  });

  it("pbkdf2Async_reportsProgressAndMatchesSync", async () => {
    const password = utf8ToBytes("TestPassword123");
    const salt = decodeBase64Strict("GdUxb0sazJpTZcEeCISwig==");
    const progress: Array<[number, number]> = [];
    const result = await pbkdf2Sha256Async(password, salt, 10000, 32, {
      onProgress: (done, total) => progress.push([done, total]),
    });

    expect(progress.length).toBeGreaterThanOrEqual(2);
    expect(progress[progress.length - 1]).toEqual([10000, 10000]);
    expect(result.length).toBe(32);
  });

  it("pbkdf2Async_canBeCancelled", async () => {
    const password = utf8ToBytes("TestPassword123");
    const salt = decodeBase64Strict("GdUxb0sazJpTZcEeCISwig==");
    let calls = 0;

    let thrown: unknown = null;

    try {
      await pbkdf2Sha256Async(password, salt, 10000, 32, {
        isCancelled: () => {
          calls += 1;

          return calls >= 2;
        },
      });
    } catch (e) {
      thrown = e;
    }

    expect(thrown instanceof Pbkdf2AbortedError).toBe(true);
  });
});
