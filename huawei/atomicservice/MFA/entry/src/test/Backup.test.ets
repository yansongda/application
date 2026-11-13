import { describe, expect, it } from '@ohos/hypium';
import {
  BackupParseError,
  checkExportPassword,
  checkImportPassword,
  formatLocalDateTime,
  parseCreatedAt,
  parseEnvelope,
  PasswordCheck
} from '../main/ets/models/Backup';
import { BackupEnvelope } from '../main/ets/types/Backup';

// 预检错误码经 catch 断言（`parseEnvelope` 直接 throw BackupParseError）
function parseErrorCode(text: string): string {
  try {
    parseEnvelope(text);

    return 'NO_ERROR';
  } catch (e) {
    if (e instanceof BackupParseError) {
      return e.code;
    }

    return 'OTHER';
  }
}

const validEnvelope = (): BackupEnvelope => {
  return {
    format: 'application',
    kind: 'totp',
    version: 1,
    meta: {
      created_at: '2026-06-28T14:30:00+08:00',
      count: 2,
    },
    kdf: {
      alg: 'pbkdf2-sha256',
      iterations: 600000,
      salt: 'AAECAwQFBgcICQoLDA0ODw==',
    },
    cipher: {
      alg: 'aes-256-gcm',
      nonce: 'AAECAwQFBgcICQoLDA0O',
    },
    data: 'Zm9vYmFy',
  };
};

const parseWith = (mutate: (envelope: BackupEnvelope) => void): string => {
  const envelope: BackupEnvelope = validEnvelope();

  mutate(envelope);

  return parseErrorCode(JSON.stringify(envelope));
};

export default function backupTest(): void {
  describe('backup_envelope', () => {
    it('parse_valid_envelope', 0, () => {
      const envelope: BackupEnvelope = parseEnvelope(JSON.stringify(validEnvelope()));

      expect(envelope.meta.count).assertEqual(2);
      expect(envelope.format).assertEqual('application');
      expect(envelope.kind).assertEqual('totp');
    });

    it('parse_rejects_invalid_json', 0, () => {
      expect(parseErrorCode('{not-json')).assertEqual('E_JSON');
    });

    it('parse_rejects_foreign_format', 0, () => {
      expect(parseWith((envelope: BackupEnvelope): void => {
        envelope.format = 'other';
      })).assertEqual('E_FORMAT');
    });

    it('parse_rejects_unsupported_kind', 0, () => {
      expect(parseWith((envelope: BackupEnvelope): void => {
        envelope.kind = 'hotp';
      })).assertEqual('E_KIND');
    });

    it('parse_rejects_future_version', 0, () => {
      expect(parseWith((envelope: BackupEnvelope): void => {
        envelope.version = 2;
      })).assertEqual('E_VERSION');
    });

    it('parse_rejects_items_over_limit', 0, () => {
      expect(parseWith((envelope: BackupEnvelope): void => {
        envelope.meta.count = 51;
      })).assertEqual('E_LIMIT');
    });

    it('parse_rejects_invalid_created_at', 0, () => {
      expect(parseWith((envelope: BackupEnvelope): void => {
        envelope.meta.created_at = '2026-02-30T10:00:00+08:00';
      })).assertEqual('E_STRUCTURE');
    });

    it('parse_rejects_missing_data', 0, () => {
      expect(parseWith((envelope: BackupEnvelope): void => {
        envelope.data = '';
      })).assertEqual('E_STRUCTURE');
    });
  });

  describe('backup_datetime', () => {
    it('parse_offset_time', 0, () => {
      const epochMs: number | undefined = parseCreatedAt('2026-06-28T14:30:00+08:00');

      expect(epochMs).assertEqual(Date.UTC(2026, 5, 28, 6, 30, 0));
    });

    it('parse_rejects_illegal_calendar', 0, () => {
      expect(parseCreatedAt('2026-13-01T00:00:00Z')).assertUndefined();
      expect(parseCreatedAt('not-a-time')).assertUndefined();
    });

    it('format_falls_back_to_raw', 0, () => {
      expect(formatLocalDateTime('not-a-time')).assertEqual('not-a-time');
    });
  });

  describe('backup_password', () => {
    it('export_rejects_short_password', 0, () => {
      const result: PasswordCheck = checkExportPassword('123');

      expect(result.ok).assertFalse();
    });

    it('export_rejects_mismatch', 0, () => {
      const result: PasswordCheck = checkExportPassword('correct-horse', 'correct-horse2');

      expect(result.ok).assertFalse();
    });

    it('export_rejects_surrounding_spaces', 0, () => {
      const result: PasswordCheck = checkExportPassword(' correct-horse ');

      expect(result.ok).assertFalse();
    });

    it('export_rejects_weak_password', 0, () => {
      const result: PasswordCheck = checkExportPassword('password');

      expect(result.ok).assertFalse();
    });

    it('export_accepts_strong_password', 0, () => {
      const result: PasswordCheck = checkExportPassword('correct-horse-battery', 'correct-horse-battery');

      expect(result.ok).assertTrue();
    });

    it('import_requires_non_empty', 0, () => {
      const result: PasswordCheck = checkImportPassword('');

      expect(result.ok).assertFalse();
    });

    it('import_accepts_short_legacy_password', 0, () => {
      const result: PasswordCheck = checkImportPassword('abc');

      expect(result.ok).assertTrue();
    });
  });
}
