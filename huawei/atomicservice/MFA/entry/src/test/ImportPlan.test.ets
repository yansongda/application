import { describe, expect, it } from '@ohos/hypium';
import { ImportReport } from '../main/ets/models/backup/ImportTypes';
import { dedupeKey } from '../main/ets/models/backup/Payload';
import { planUriIssuer, URI_ISSUER_PLACEHOLDER } from '../main/ets/models/backup/Spec';

export default function importPlanTest(): void {
  describe('backupImportPlan', () => {
    it('planUriIssuer_plainIssuerKept', 0, () => {
      expect(planUriIssuer('GitHub')).assertEqual('GitHub');
    });

    it('planUriIssuer_colonIssuerUsesPlaceholder', 0, () => {
      expect(planUriIssuer('A:B')).assertEqual(URI_ISSUER_PLACEHOLDER);
    });

    it('planUriIssuer_emptyIssuerUsesPlaceholder', 0, () => {
      expect(planUriIssuer('')).assertEqual(URI_ISSUER_PLACEHOLDER);
    });

    it('planUriIssuer_placeholderHasNoColon', 0, () => {
      expect(URI_ISSUER_PLACEHOLDER.includes(':')).assertFalse();
    });

    it('dedupeKey_format', 0, () => {
      expect(dedupeKey('ABC', 'Issuer', 'user')).assertEqual('ABC|Issuer|user');
    });

    it('dedupeKey_keepsColonValuesVerbatim', 0, () => {
      expect(dedupeKey('ABC', 'A:B', 'a:b')).assertEqual('ABC|A:B|a:b');
    });

    it('report_defaults', 0, () => {
      const report: ImportReport = new ImportReport();

      expect(report.done).assertEqual(0);
      expect(report.failed.length).assertEqual(0);
      expect(report.canceled).assertFalse();
      expect(report.notExecuted).assertEqual(0);
      expect(report.withTags).assertEqual(0);
      expect(report.withPinned).assertEqual(0);
    });
  });
}
