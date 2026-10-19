import { describe, expect, it } from '@ohos/hypium';
import { OtpAlgorithm, TOTP } from '@yansongda/otp';

// 设备侧用例：覆盖 @yansongda/otp 的真实 crypto 路径（HMAC-SHA1 / SHA256 / SHA512）。
// 官方「本地测试（Local Test）」不支持系统 API，真 crypto 只能在设备/模拟器侧执行。
// 向量来源：RFC 4226 Appendix D / RFC 6238 Appendix B / A.6，secret 依次为
// base32('12345678901234567890')、base32(32 字节 '123...32')、base32(64 字节 '123...64')。
const RFC_SECRET: string = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
const RFC_SECRET_SHA256: string = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA';
const RFC_SECRET_SHA512: string =
  'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA';

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

    it('generate_sha1_8digits_rfcVector_T59', 0, () => {
      const code: string = new TOTP({ secret: RFC_SECRET, digits: 8, period: 30 }).generate(59000);
      expect(code).assertEqual('94287082');
    });

    it('generate_sha1_7digits_rfcVector_T59', 0, () => {
      const code: string = new TOTP({ secret: RFC_SECRET, digits: 7, period: 30 }).generate(59000);
      expect(code).assertEqual('4287082');
    });

    it('generate_sha256_8digits_rfcVector_T59', 0, () => {
      const code: string = new TOTP({
        secret: RFC_SECRET_SHA256,
        algorithm: OtpAlgorithm.SHA256,
        digits: 8,
        period: 30
      }).generate(59000);
      expect(code).assertEqual('46119246');
    });

    it('generate_sha512_8digits_rfcVector_T59', 0, () => {
      const code: string = new TOTP({
        secret: RFC_SECRET_SHA512,
        algorithm: OtpAlgorithm.SHA512,
        digits: 8,
        period: 30
      }).generate(59000);
      expect(code).assertEqual('90693936');
    });
  });
}
