import { describe, it, expect } from '@ohos/hypium';
import { shouldRelock, shouldDebounceVerify, LOCK_TIMEOUT_MS, VERIFY_DEBOUNCE_MS } from '../main/ets/utils/AppLockPolicy';

// 固定基准时间戳，避免逐条用例重复声明
const NOW: number = 1700000000000;

export default function appLockPolicyTest(): void {
  describe('appLockPolicy', () => {
    // 锁定判定（技术设计 §3.10 表格逐条）；边界用导出的常量表达，阈值调整后用例自动跟随
    it('shouldRelock_appLock_false', 0, () => {
      expect(shouldRelock(false, NOW - LOCK_TIMEOUT_MS, NOW)).assertEqual(false);
    });
    it('shouldRelock_backgroundAt_undefined', 0, () => {
      expect(shouldRelock(true, undefined, NOW)).assertEqual(false);
    });
    it('shouldRelock_delta_below_timeout', 0, () => {
      expect(shouldRelock(true, NOW - LOCK_TIMEOUT_MS + 1, NOW)).assertEqual(false);
    });
    it('shouldRelock_delta_timeout', 0, () => {
      expect(shouldRelock(true, NOW - LOCK_TIMEOUT_MS, NOW)).assertEqual(true);
    });
    it('shouldRelock_clock_rollback', 0, () => {
      expect(shouldRelock(true, NOW + 1000, NOW)).assertEqual(false);
    });

    // 验证防抖判定（时钟回拨 → 放行，否则首次验证被自身防抖挡住 → 永久锁死）
    it('shouldDebounceVerify_finishedAt_undefined', 0, () => {
      expect(shouldDebounceVerify(undefined, NOW)).assertEqual(false);
    });
    it('shouldDebounceVerify_delta_below_debounce', 0, () => {
      expect(shouldDebounceVerify(NOW - VERIFY_DEBOUNCE_MS + 1, NOW)).assertEqual(true);
    });
    it('shouldDebounceVerify_delta_debounce', 0, () => {
      expect(shouldDebounceVerify(NOW - VERIFY_DEBOUNCE_MS, NOW)).assertEqual(false);
    });
    it('shouldDebounceVerify_clock_rollback', 0, () => {
      expect(shouldDebounceVerify(NOW + 1000, NOW)).assertEqual(false);
    });
  });
}
