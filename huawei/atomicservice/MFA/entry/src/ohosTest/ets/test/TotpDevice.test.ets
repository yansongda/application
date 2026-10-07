import { describe, expect, it } from '@ohos/hypium';
import { TOTP } from '@yansongda/otp';

// 设备侧用例：覆盖 @yansongda/otp 的真实 crypto 路径（HMAC-SHA1）。
// 官方「本地测试（Local Test）」不支持系统 API，真 crypto 只能在设备/模拟器侧执行。
// 向量来源：RFC 4226 Appendix D / RFC 6238 Appendix B（SHA1 / 6 位 / period=30），
// secret = base32('12345678901234567890')。
const RFC_SECRET: string = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

export default function totpDeviceTest() {
  describe('totpDeviceTest', () => {
    it('generate_rfcVector_T59', 0, () => {
      const code: string = new TOTP({ secret: RFC_SECRET, period: 30 }).generate(59000);
      expect(code).assertEqual('287082');
    });

    it('generate_rfcVector_T1234567890', 0, () => {
      const code: string = new TOTP({ secret: RFC_SECRET, period: 30 }).generate(1234567890000);
      expect(code).assertEqual('005924');
    });

    it('remaining_alignToEpoch', 0, () => {
      const remaining: number = new TOTP({ secret: RFC_SECRET, period: 30 }).remaining(59000);
      expect(remaining).assertEqual(1);
    });

    it('generate_defaultTimestamp_sixDigits', 0, () => {
      const code: string = new TOTP({ secret: RFC_SECRET, period: 30 }).generate();
      expect(code.length).assertEqual(6);
      expect(Number.isNaN(Number(code))).assertFalse();
    });
  });
}
