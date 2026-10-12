import { describe, it, expect } from '@ohos/hypium';
import { shouldRelock, shouldDebounceVerify } from '../main/ets/utils/LockPolicy';

export default function lockPolicyTest(): void {
  describe('lockPolicy', () => {
    // 锁定判定（技术设计 §3.10 表格逐条）
    it('shouldRelock_appLock_false', 0, () => {
      const now: number = 1700000000000;

      expect(shouldRelock(false, now - 99999, now)).assertEqual(false);
    });
    it('shouldRelock_backgroundAt_undefined', 0, () => {
      const now: number = 1700000000000;

      expect(shouldRelock(true, undefined, now)).assertEqual(false);
    });
    it('shouldRelock_delta_59999', 0, () => {
      const now: number = 1700000000000;

      expect(shouldRelock(true, now - 59999, now)).assertEqual(false);
    });
    it('shouldRelock_delta_60000', 0, () => {
      const now: number = 1700000000000;

      expect(shouldRelock(true, now - 60000, now)).assertEqual(true);
    });
    it('shouldRelock_clock_rollback', 0, () => {
      const now: number = 1700000000000;

      expect(shouldRelock(true, now + 1000, now)).assertEqual(false);
    });

    // 验证防抖判定（时钟回拨 → 放行，否则首次验证被自身防抖挡住 → 永久锁死）
    it('shouldDebounceVerify_finishedAt_undefined', 0, () => {
      const now: number = 1700000000000;

      expect(shouldDebounceVerify(undefined, now)).assertEqual(false);
    });
    it('shouldDebounceVerify_delta_2999', 0, () => {
      const now: number = 1700000000000;

      expect(shouldDebounceVerify(now - 2999, now)).assertEqual(true);
    });
    it('shouldDebounceVerify_delta_3000', 0, () => {
      const now: number = 1700000000000;

      expect(shouldDebounceVerify(now - 3000, now)).assertEqual(false);
    });
    it('shouldDebounceVerify_clock_rollback', 0, () => {
      const now: number = 1700000000000;

      expect(shouldDebounceVerify(now + 1000, now)).assertEqual(false);
    });
  });
}
