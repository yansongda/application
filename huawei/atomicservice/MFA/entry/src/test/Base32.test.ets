import { describe, expect, it } from '@ohos/hypium';
import { canonicalSecret, replaceSecretInUri, secretOfOtpauthUri } from '../../main/ets/utils/Base32';

// 密钥校验依赖 @yansongda/otp 的 Secret 解码/编码语义，必须用真实库跑，不能只靠常量断言
export default function base32Test() {
  describe('base32Test', () => {
    it('canonicalSecretAcceptsLosslessSecret', 0, () => {
      expect(canonicalSecret('JBSWY3DPEHPK3PXP')).assertEqual('JBSWY3DPEHPK3PXP');
      // 小写与空白都被库的宽松解析吸收，输出统一大写
      expect(canonicalSecret('jbswy3dpehpk3pxp')).assertEqual('JBSWY3DPEHPK3PXP');
      expect(canonicalSecret(' GE ')).assertEqual('GE');
      // 尾长 0/2 且填充位为 0：后端解码后重新编码仍是原值
      expect(canonicalSecret('GE')).assertEqual('GE');
      expect(canonicalSecret('GGGA')).assertEqual('GGGA');
    });

    it('canonicalSecretRejectsTruncatedSecret', 0, () => {
      // GGG 只有 15 bit，后端按 len*5/8=1 字节截断后入库变成 GE
      expect(canonicalSecret('GGG')).assertUndefined();
      // GG 的尾部填充位非 0，往返后变成 GA
      expect(canonicalSecret('GG')).assertUndefined();
      expect(canonicalSecret('GGG GGG')).assertUndefined();
      expect(canonicalSecret('')).assertUndefined();
      // 非 base32 字符集
      expect(canonicalSecret('1888')).assertUndefined();
    });

    it('secretOfOtpauthUriAndReplace', 0, () => {
      const uri = 'otpauth://totp/a:b?secret=jbswy3dpehpk3pxp&issuer=a&period=30&digits=6&algorithm=SHA1';
      const raw: string | undefined = secretOfOtpauthUri(uri);

      expect(raw).assertEqual('jbswy3dpehpk3pxp');

      const canonical: string | undefined = 'undefined' === typeof raw ? undefined : canonicalSecret(raw);

      expect(canonical).assertEqual('JBSWY3DPEHPK3PXP');
      expect('undefined' === typeof canonical ? uri : replaceSecretInUri(uri, canonical))
        .assertEqual('otpauth://totp/a:b?secret=JBSWY3DPEHPK3PXP&issuer=a&period=30&digits=6&algorithm=SHA1');
      // 没有 secret 参数时不改写
      expect(secretOfOtpauthUri('otpauth://totp/a:b?issuer=a')).assertUndefined();
    });
  });
}
