import { describe, it, expect } from '@ohos/hypium';
import { SessionThrottle, DEBOUNCE_MS, WINDOW_MS, LIMIT } from '../main/ets/utils/SessionThrottle';

// 固定基准时间戳，避免逐条用例重复声明
const NOW: number = 1700000000000;

export default function sessionThrottleTest(): void {
  describe('sessionThrottle', () => {
    it('first_redirect_allowed', 0, () => {
      const throttle: SessionThrottle = new SessionThrottle();

      expect(throttle.allow(NOW)).assertTrue();
    });

    it('debounce_within_window_rejected', 0, () => {
      const throttle: SessionThrottle = new SessionThrottle();

      expect(throttle.allow(NOW)).assertTrue();
      throttle.finish();

      expect(throttle.allow(NOW + DEBOUNCE_MS - 1)).assertFalse();
    });

    it('debounce_after_window_allowed', 0, () => {
      const throttle: SessionThrottle = new SessionThrottle();

      expect(throttle.allow(NOW)).assertTrue();
      throttle.finish();

      expect(throttle.allow(NOW + DEBOUNCE_MS)).assertTrue();
    });

    it('single_flight_rejected_while_redirecting', 0, () => {
      const throttle: SessionThrottle = new SessionThrottle();

      expect(throttle.allow(NOW)).assertTrue();
      // 未调用 finish：单飞期间任何信号都应被丢弃
      expect(throttle.allow(NOW + DEBOUNCE_MS + 1)).assertFalse();
    });

    it('limit_reached_rejected', 0, () => {
      const throttle: SessionThrottle = new SessionThrottle();

      for (let i = 0; i < LIMIT; i++) {
        expect(throttle.allow(NOW + i * (DEBOUNCE_MS + 1))).assertTrue();
        throttle.finish();
      }

      expect(throttle.count).assertEqual(LIMIT);
      expect(throttle.allow(NOW + LIMIT * (DEBOUNCE_MS + 1))).assertFalse();
    });

    it('window_expired_resets_count', 0, () => {
      const throttle: SessionThrottle = new SessionThrottle();

      for (let i = 0; i < LIMIT; i++) {
        expect(throttle.allow(NOW + i * (DEBOUNCE_MS + 1))).assertTrue();
        throttle.finish();
      }

      expect(throttle.allow(NOW + WINDOW_MS + 1)).assertTrue();
      expect(throttle.count).assertEqual(1);
    });

    it('reset_after_login_clears_debounce_but_keeps_count', 0, () => {
      const throttle: SessionThrottle = new SessionThrottle();

      expect(throttle.allow(NOW)).assertTrue();
      throttle.finish();

      throttle.resetAfterLogin();

      // 去抖标记被清空：下一次信号立刻放行
      expect(throttle.allow(NOW + 1)).assertTrue();
      // 60s 计数保留（防止异常场景无限跳转）
      expect(throttle.count).assertEqual(2);
    });
  });
}
