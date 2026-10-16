import { describe, it, expect } from '@ohos/hypium';
import { shouldRelock, shouldDebounceVerify } from '../main/ets/utils/LockPolicy';

// 固定基准时间戳，避免逐条用例重复声明
const NOW: number = 1700000000000;

export default function lockPolicyTest(): void {
  describe('lockPolicy', () => {
    // 锁定判定（技术设计 §3.10 表格逐条）
    it('shouldRelock_appLock_false', 0, () => {
      expect(shouldRelock(false, NOW - 99999, NOW)).assertEqual(false);
    });
    it('shouldRelock_backgroundAt_undefined', 0, () => {
      expect(shouldRelock(true, undefined, NOW)).assertEqual(false);
    });
    it('shouldRelock_delta_59999', 0, () => {
      expect(shouldRelock(true, NOW - 59999, NOW)).assertEqual(false);
    });
    it('shouldRelock_delta_60000', 0, () => {
      expect(shouldRelock(true, NOW - 60000, NOW)).assertEqual(true);
    });
    it('shouldRelock_clock_rollback', 0, () => {
      expect(shouldRelock(true, NOW + 1000, NOW)).assertEqual(false);
    });

    // 验证防抖判定（时钟回拨 → 放行，否则首次验证被自身防抖挡住 → 永久锁死）
    it('shouldDebounceVerify_finishedAt_undefined', 0, () => {
      expect(shouldDebounceVerify(undefined, NOW)).assertEqual(false);
    });
    it('shouldDebounceVerify_delta_2999', 0, () => {
      expect(shouldDebounceVerify(NOW - 2999, NOW)).assertEqual(true);
    });
    it('shouldDebounceVerify_delta_3000', 0, () => {
      expect(shouldDebounceVerify(NOW - 3000, NOW)).assertEqual(false);
    });
    it('shouldDebounceVerify_clock_rollback', 0, () => {
      expect(shouldDebounceVerify(NOW + 1000, NOW)).assertEqual(false);
    });
  });
}
