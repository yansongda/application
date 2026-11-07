// 导出编排：账号列表 → 校验/归一 → 口令加密 → .mfa 文本。
// 缺 secret 或无法归一（非法 Base32 / period）的条目跳过并计数，不阻塞整体导出。
import { IItem } from '../../types/Item';
import { BackupCrypto } from './Crypto';
import { encodeBase64 } from './Envelope';
import { IEnvelope, stringifyEnvelope } from './Envelope';
import { IBackupItem, IRawItem, sanitizeItem, stringifyPayload } from './Payload';
import { BackupError, BackupErrorCode, BackupSpec } from './Spec';

export class ExportResult {
  readonly text: string;
  readonly count: number;
  readonly skipped: number;

  constructor(text: string, count: number, skipped: number) {
    this.text = text;
    this.count = count;
    this.skipped = skipped;
  }
}

export class Exporter {
  static async build(items: IItem[], password: string, app: string): Promise<ExportResult> {
    const editable: IBackupItem[] = [];
    let skipped: number = 0;

    for (const item of items) {
      const secret: string | undefined = item.config.secret;

      if ('undefined' === typeof secret || secret.length === 0) {
        skipped++;
        continue;
      }

      const raw: IRawItem = {
        issuer: item.issuer,
        username: item.username,
        secret: secret,
        period: item.config.period,
        digits: item.config.digits,
        algorithm: item.config.algorithm,
        tags: item.tags,
        pinned: item.pinned
      };
      const sanitized = sanitizeItem(raw);

      if (!sanitized.ok || 'undefined' === typeof sanitized.item) {
        skipped++;
        continue;
      }

      editable.push(sanitized.item);
    }

    if (editable.length > BackupSpec.MAX_ITEMS) {
      throw new BackupError(BackupErrorCode.E_PAYLOAD, `单包条目数超过上限 ${BackupSpec.MAX_ITEMS}`);
    }

    const strengthMessage: string | undefined = BackupCrypto.checkPassword(password);

    if ('undefined' !== typeof strengthMessage) {
      throw new BackupError(BackupErrorCode.E_STRUCTURE, strengthMessage);
    }

    const salt: Uint8Array = BackupCrypto.randomBytes(BackupSpec.SALT_BYTES);
    const iv: Uint8Array = BackupCrypto.randomBytes(BackupSpec.IV_BYTES);
    const key: Uint8Array = await BackupCrypto.deriveKey(password, salt, BackupSpec.DEFAULT_ITERATIONS);
    const kcv: Uint8Array = await BackupCrypto.kcv(key);
    const body: Uint8Array = BackupCrypto.utf8Bytes(stringifyPayload(editable));
    const encrypted = await BackupCrypto.encrypt(key, iv, BackupCrypto.utf8Bytes(BackupSpec.AAD), body);

    const envelope: IEnvelope = {
      format: BackupSpec.FORMAT,
      version: BackupSpec.VERSION,
      method: BackupSpec.METHOD,
      key: {
        iterations: BackupSpec.DEFAULT_ITERATIONS,
        salt: encodeBase64(salt),
        iv: encodeBase64(iv),
        tag: encodeBase64(encrypted.tag),
        kcv: encodeBase64(kcv)
      },
      data: encodeBase64(encrypted.ciphertext),
      meta: {
        count: editable.length,
        createdAt: new Date().toISOString(),
        source: 'huawei',
        app: app
      }
    };

    return new ExportResult(stringifyEnvelope(envelope), editable.length, skipped);
  }
}
