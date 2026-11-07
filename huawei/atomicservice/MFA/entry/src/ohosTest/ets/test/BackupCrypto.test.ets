import { describe, expect, it } from '@ohos/hypium';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../../../main/ets/App';
import { BackupCrypto } from '../../../main/ets/models/backup/Crypto';
import { decodeBase64Strict, encodeBase64, parseEnvelope } from '../../../main/ets/models/backup/Envelope';
import { BACKUP_AAD, BACKUP_VECTORS, IBackupVectorCase } from './BackupVectors';

// 设备侧用例：对齐 docs/specs/mfa-backup-v1.vectors.json（oracle = node:crypto），
// 覆盖 PBKDF2 / AES-256-GCM / kcv / 解密回环。真 crypto 只能在设备或模拟器执行。

function bytesToHex(bytes: Uint8Array): string {
  let out: string = '';

  for (let i = 0; i < bytes.length; i++) {
    const value: number = bytes[i];
    const hex: string = value.toString(16);

    out += value < 16 ? `0${hex}` : hex;
  }

  return out;
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');

  await md.update({ data: bytes });

  const digest: cryptoFramework.DataBlob = await md.digest();

  return bytesToHex(digest.data);
}

function plaintextOf(c: IBackupVectorCase): Uint8Array {
  return c.plaintextB64.length > 0
    ? decodeBase64Strict(c.plaintextB64)
    : BackupCrypto.utf8Bytes(c.payloadJson);
}

function findCase(id: string): IBackupVectorCase | undefined {
  for (const c of BACKUP_VECTORS) {
    if (c.id === id) {
      return c;
    }
  }

  return undefined;
}

export default function backupCryptoTest() {
  describe('backupCrypto', () => {
    it('aadAndKcvLabelMatchSpec', 0, () => {
      expect(BACKUP_AAD).assertEqual(BackupCrypto.utf8Text(BackupCrypto.utf8Bytes('mfa|1|PBKDF2-SHA256/AES-256-GCM')));
      expect(BACKUP_VECTORS.length).assertEqual(15);
    });

    it('deriveKey_matchesAllVectors', 0, async () => {
      for (const c of BACKUP_VECTORS) {
        const key: Uint8Array = await BackupCrypto.deriveKey(c.passwordRaw,
          decodeBase64Strict(c.saltB64), c.iterations);

        expect(encodeBase64(key)).assertEqual(c.keyB64);
      }
    });

    it('kcv_matchesAllVectors', 0, async () => {
      for (const c of BACKUP_VECTORS) {
        const key: Uint8Array = decodeBase64Strict(c.keyB64);

        expect(encodeBase64(await BackupCrypto.kcv(key))).assertEqual(c.kcvB64);
      }
    });

    it('encrypt_matchesAllVectors', 0, async () => {
      for (const c of BACKUP_VECTORS) {
        const key: Uint8Array = decodeBase64Strict(c.keyB64);
        const encrypted = await BackupCrypto.encrypt(key, decodeBase64Strict(c.ivB64),
          BackupCrypto.utf8Bytes(BACKUP_AAD), plaintextOf(c));

        expect(encodeBase64(encrypted.ciphertext)).assertEqual(c.ciphertextB64);
        expect(encodeBase64(encrypted.tag)).assertEqual(c.tagB64);
      }
    });

    it('decrypt_roundTripsAllVectors', 0, async () => {
      for (const c of BACKUP_VECTORS) {
        const plaintext: Uint8Array | undefined = await BackupCrypto.decrypt(
          decodeBase64Strict(c.keyB64),
          decodeBase64Strict(c.ivB64),
          BackupCrypto.utf8Bytes(BACKUP_AAD),
          decodeBase64Strict(c.ciphertextB64),
          decodeBase64Strict(c.tagB64));

        expect(plaintext !== undefined).assertTrue();

        if ('undefined' === typeof plaintext) {
          continue;
        }

        expect(await sha256Hex(plaintext)).assertEqual(c.payloadSha256);
      }
    });

    it('decrypt_wrongTagReturnsUndefined', 0, async () => {
      const c: IBackupVectorCase = BACKUP_VECTORS[0];
      const tag: Uint8Array = decodeBase64Strict(c.tagB64);

      tag[0] = tag[0] ^ 0x01;

      const plaintext: Uint8Array | undefined = await BackupCrypto.decrypt(
        decodeBase64Strict(c.keyB64),
        decodeBase64Strict(c.ivB64),
        BackupCrypto.utf8Bytes(BACKUP_AAD),
        decodeBase64Strict(c.ciphertextB64),
        tag);

      expect(plaintext === undefined).assertTrue();
    });

    it('kcv_wrongPasswordDoesNotMatch', 0, async () => {
      const c: IBackupVectorCase = BACKUP_VECTORS[0];
      const wrongKey: Uint8Array = await BackupCrypto.deriveKey('WrongPassword123',
        decodeBase64Strict(c.saltB64), c.iterations);

      expect(encodeBase64(await BackupCrypto.kcv(wrongKey)) === c.kcvB64).assertFalse();
    });

    it('parseAndDecrypt_case12Envelope', 0, async () => {
      const c: IBackupVectorCase | undefined = findCase('case-12');

      expect(c !== undefined).assertTrue();

      if ('undefined' === typeof c) {
        return;
      }

      const envelopeText: string = '{"format":"mfa","version":1,"method":"PBKDF2-SHA256/AES-256-GCM",' +
        `"key":{"iterations":${c.iterations},"salt":"${c.saltB64}","iv":"${c.ivB64}",` +
        `"tag":"${c.tagB64}","kcv":"${c.kcvB64}"},"data":"${c.ciphertextB64}",` +
        '"meta":{"count":1,"createdAt":"2026-11-07T00:00:00.000Z","source":"huawei","app":"1.9.0"}}';
      const parsed = parseEnvelope(envelopeText);

      expect(parsed.ok).assertTrue();

      if (!parsed.ok || 'undefined' === typeof parsed.envelope) {
        return;
      }

      const key: Uint8Array = await BackupCrypto.deriveKey(c.passwordRaw,
        decodeBase64Strict(parsed.envelope.key.salt), parsed.envelope.key.iterations);

      expect(encodeBase64(await BackupCrypto.kcv(key))).assertEqual(parsed.envelope.key.kcv);

      const plaintext: Uint8Array | undefined = await BackupCrypto.decrypt(key,
        decodeBase64Strict(parsed.envelope.key.iv),
        BackupCrypto.utf8Bytes(BACKUP_AAD),
        decodeBase64Strict(parsed.envelope.data),
        decodeBase64Strict(parsed.envelope.key.tag));

      expect(plaintext !== undefined).assertTrue();

      if ('undefined' !== typeof plaintext) {
        expect(await sha256Hex(plaintext)).assertEqual(c.payloadSha256);
      }
    });

    it('deriveKey_defaultIterationsPerformance', 0, async () => {
      const c: IBackupVectorCase | undefined = findCase('case-11');

      expect(c !== undefined).assertTrue();

      if ('undefined' === typeof c) {
        return;
      }

      const startedAt: number = Date.now();

      await BackupCrypto.deriveKey(c.passwordRaw, decodeBase64Strict(c.saltB64), c.iterations);

      const elapsed: number = Date.now() - startedAt;

      hilog.info(LogDomain.MODELS, 'models/backup', 'PBKDF2 %{public}d 次迭代耗时 %{public}dms',
        c.iterations, elapsed);

      expect(elapsed > 0).assertTrue();
    });
  });
}
