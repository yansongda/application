import { describe, expect, it } from '@ohos/hypium';
import {
  dedupeKey,
  parsePayload,
  sanitizeItem,
  stringifyPayload
} from '../main/ets/models/backup/Payload';
import { BackupErrorCode } from '../main/ets/models/backup/Spec';

const ITEM_JSON: string = '{"issuer":"GitHub","username":"alice@example.com",' +
  '"secret":"JBSWY3DPEHPK3PXP","period":30,"digits":6,"algorithm":"SHA1",' +
  '"tags":["工作"],"pinned":true}';

function payloadOf(items: string): string {
  return `{"v":1,"items":[${items}]}`;
}

function codeOf(text: string): string {
  const result = parsePayload(text);

  return result.ok ? 'OK' : result.code.toString();
}

export default function payloadTest(): void {
  describe('backupPayload', () => {
    it('parse_validPayload', 0, () => {
      const result = parsePayload(payloadOf(ITEM_JSON));

      expect(result.ok).assertTrue();
      expect(result.items.length).assertEqual(1);
      expect(result.invalid.length).assertEqual(0);
      expect(result.items[0].secret).assertEqual('JBSWY3DPEHPK3PXP');
      expect(result.items[0].tags.length).assertEqual(1);
      expect(result.items[0].pinned).assertTrue();
    });

    it('parse_roundTripsThroughStringify', 0, () => {
      const parsed = parsePayload(payloadOf(ITEM_JSON));
      const text: string = stringifyPayload(parsed.items);
      const again = parsePayload(text);

      expect(again.ok).assertTrue();
      expect(again.items.length).assertEqual(1);
      expect(again.items[0].issuer).assertEqual('GitHub');
    });

    it('parse_emptyItemsAllowed', 0, () => {
      const result = parsePayload('{"v":1,"items":[]}');

      expect(result.ok).assertTrue();
      expect(result.items.length).assertEqual(0);
    });

    it('parse_wrongVersionIsEPayload', 0, () => {
      expect(codeOf('{"v":2,"items":[]}')).assertEqual(BackupErrorCode.E_PAYLOAD.toString());
    });

    it('parse_nonJsonIsEPayload', 0, () => {
      expect(codeOf('not json')).assertEqual(BackupErrorCode.E_PAYLOAD.toString());
    });

    it('parse_tooManyItemsIsEPayload', 0, () => {
      const items: string[] = [];

      for (let i = 0; i < 501; i++) {
        items.push(ITEM_JSON);
      }

      expect(codeOf(payloadOf(items.join(',')))).assertEqual(BackupErrorCode.E_PAYLOAD.toString());
    });

    it('parse_invalidItemDoesNotBlockOthers', 0, () => {
      const truncated: string = ITEM_JSON.replace('"JBSWY3DPEHPK3PXP"', '"JBSWY3DPEHPK3P"');
      const result = parsePayload(payloadOf(`${ITEM_JSON},${truncated},${ITEM_JSON}`));

      expect(result.ok).assertTrue();
      expect(result.items.length).assertEqual(2);
      expect(result.invalid.length).assertEqual(1);
      expect(result.invalid[0].index).assertEqual(1);
    });

    it('sanitize_fallsBackForDigitsAndAlgorithm', 0, () => {
      const result = sanitizeItem({
        issuer: 'GitHub',
        username: 'alice',
        secret: 'JBSWY3DPEHPK3PXP',
        period: 30,
        digits: 9,
        algorithm: 'MD5'
      });

      expect(result.ok).assertTrue();
      expect(result.item?.digits).assertEqual(6);
      expect(result.item?.algorithm).assertEqual('SHA1');
    });

    it('sanitize_keepsSupportedDigitsAndAlgorithm', 0, () => {
      const result = sanitizeItem({
        issuer: 'GitHub',
        username: 'alice',
        secret: 'jbswy3dpehpk3pxp',
        period: 60,
        digits: 8,
        algorithm: 'sha256'
      });

      expect(result.ok).assertTrue();
      expect(result.item?.digits).assertEqual(8);
      expect(result.item?.algorithm).assertEqual('SHA256');
      expect(result.item?.secret).assertEqual('JBSWY3DPEHPK3PXP');
    });

    it('sanitize_periodAndIssuerBounds', 0, () => {
      const periodZero = sanitizeItem({
        issuer: 'GitHub',
        username: 'alice',
        secret: 'JBSWY3DPEHPK3PXP',
        period: 0
      });

      expect(periodZero.ok).assertFalse();

      const longIssuer = sanitizeItem({
        issuer: 'x'.repeat(129),
        username: 'alice',
        secret: 'JBSWY3DPEHPK3PXP',
        period: 30
      });

      expect(longIssuer.ok).assertFalse();
    });

    it('sanitize_tagsTruncatedToOne', 0, () => {
      const result = sanitizeItem({
        issuer: 'GitHub',
        username: 'alice',
        secret: 'JBSWY3DPEHPK3PXP',
        period: 30,
        tags: ['', 'x'.repeat(33), '工作', '备份']
      });

      expect(result.ok).assertTrue();
      expect(result.item?.tags.length).assertEqual(1);
      expect(result.item?.tags[0]).assertEqual('工作');
    });

    it('sanitize_colonIssuerAndUsernameAllowed', 0, () => {
      expect(sanitizeItem({
        issuer: 'A:B',
        username: 'a:b',
        secret: 'JBSWY3DPEHPK3PXP',
        period: 30
      }).ok).assertTrue();
    });

    it('dedupeKey_isSecretIssuerUsername', 0, () => {
      expect(dedupeKey('JBSWY3DPEHPK3PXP', 'GitHub', 'alice'))
        .assertEqual('JBSWY3DPEHPK3PXP|GitHub|alice');
    });
  });
}
