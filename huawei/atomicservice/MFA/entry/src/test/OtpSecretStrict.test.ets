import { describe, expect, it } from '@ohos/hypium';
import { OTPAuthURI, OtpError, OtpErrorCode, Secret } from '@yansongda/otp';

// 依赖 @yansongda/otp >= 1.1.0 的 strict 解析：拒绝「解码再编码无法原样往返」的 Base32 密钥。
// 这是元服务新建 / 扫码路径唯一的密钥校验入口（后端会把非规范密钥静默截断后入库，GGG → GE）。

function strictErrorCode(input: string): string | undefined {
  try {
    Secret.fromBase32(input, { strict: true });

    return undefined;
  } catch (e) {
    const error: OtpError = e as OtpError;

    return error.code;
  }
}

export default function otpSecretStrictTest() {
  describe('otpSecretStrictTest', () => {
    it('strictAcceptsCanonicalSecret', 0, () => {
      expect(Secret.fromBase32('JBSWY3DPEHPK3PXP', { strict: true }).toBase32())
        .assertEqual('JBSWY3DPEHPK3PXP');
      // 大小写 / 空白 / 尾部填充仍被容忍，输出统一为规范值
      expect(Secret.fromBase32('jbswy3dpehpk3pxp', { strict: true }).toBase32())
        .assertEqual('JBSWY3DPEHPK3PXP');
      expect(Secret.fromBase32(' GE ', { strict: true }).toBase32()).assertEqual('GE');
      expect(Secret.fromBase32('GGGA', { strict: true }).toBase32()).assertEqual('GGGA');
    });

    it('strictRejectsSecretThatWouldBeTruncated', 0, () => {
      // GGG 只有 15 bit：尾长 3 非法，宽松模式会被截断成 GE
      expect(strictErrorCode('GGG')).assertEqual(OtpErrorCode.INVALID_BASE32_PADDING);
      // GG 尾长合法但填充位非 0，宽松往返后变成 GA
      expect(strictErrorCode('GG')).assertEqual(OtpErrorCode.INVALID_BASE32_PADDING);
      // 归一化后变成 6 个字符（尾长 6），同样非法
      expect(strictErrorCode('GGG GGG')).assertEqual(OtpErrorCode.INVALID_BASE32_PADDING);
    });

    it('strictParseRejectsUriWithTruncatedSecret', 0, () => {
      let errorCode: string | undefined = undefined;

      try {
        OTPAuthURI.parse('otpauth://totp/Example:alice?secret=GGG&issuer=Example', { strict: true });
      } catch (e) {
        const error: OtpError = e as OtpError;

        errorCode = error.code;
      }

      expect(errorCode).assertEqual(OtpErrorCode.INVALID_BASE32_PADDING);

      // 规范密钥：解析出规范值，重建 URI 后仍可被 strict 解析（扫码路径依赖这条环路）
      const params = OTPAuthURI.parse('otpauth://totp/Example:alice?secret=jbswy3dpehpk3pxp&issuer=Example',
        { strict: true });

      expect(params.secret).assertEqual('JBSWY3DPEHPK3PXP');
      expect(OTPAuthURI.parse(OTPAuthURI.build(params), { strict: true }).secret)
        .assertEqual('JBSWY3DPEHPK3PXP');
    });
  });
}
