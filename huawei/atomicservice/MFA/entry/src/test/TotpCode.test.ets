import { describe, expect, it } from '@ohos/hypium';
// 只加载纯计算模块（无系统 kit 依赖），避免本地单测加载 cryptoFramework。
import { base32Decode, counterToBytes, truncate, zeroPad6 } from '../main/ets/utils/TotpMath';

export default function totpCodeTest() {
  describe('totpCodeTest', () => {
    it('base32Decode_rfcSecret', 0, () => {
      const secret: string = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
      const bytes: Uint8Array = base32Decode(secret);
      expect(bytes.length).assertEqual(20);
      expect(bytes[0]).assertEqual(49);
      expect(bytes[19]).assertEqual(48);
    });

    it('base32Decode_tailGroupTruncate', 0, () => {
      // 'MY'（2 字符末组）应解出 1 字节 0x66（102）。
      const bytes: Uint8Array = base32Decode('MY');
      expect(bytes.length).assertEqual(1);
      expect(bytes[0]).assertEqual(102);
    });

    it('base32Decode_normalizeEquivalence', 0, () => {
      // 小写、含 '=' 填充、含空白，均应与大写无填充输入解码结果一致。
      const secret: string = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
      const reference: Uint8Array = base32Decode(secret);
      const lower: Uint8Array = base32Decode('gezdgnbvg y3tqojqgezdgnbvgy3tqojq');
      const padded: Uint8Array = base32Decode('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ======');
      expect(lower.length).assertEqual(reference.length);
      expect(padded.length).assertEqual(reference.length);
      for (let i = 0; i < reference.length; i++) {
        expect(lower[i]).assertEqual(reference[i]);
        expect(padded[i]).assertEqual(reference[i]);
      }
    });

    it('base32Decode_emptyThrows', 0, () => {
      let threw: boolean = false;
      try {
        base32Decode('');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('base32Decode_zeroByteThrows', 0, () => {
      // 'A' 解码后 0 字节，应抛「长度不足」。
      let threw: boolean = false;
      try {
        base32Decode('A');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('base32Decode_illegalCharThrows', 0, () => {
      // '1' 不在 A-Z2-7 字母表，应抛「含非法字符」。
      let threw: boolean = false;
      try {
        base32Decode('AB1');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('counterToBytes_small', 0, () => {
      const bytes: Uint8Array = counterToBytes(1);
      expect(bytes.length).assertEqual(8);
      expect(bytes[0]).assertEqual(0);
      expect(bytes[1]).assertEqual(0);
      expect(bytes[2]).assertEqual(0);
      expect(bytes[3]).assertEqual(0);
      expect(bytes[4]).assertEqual(0);
      expect(bytes[5]).assertEqual(0);
      expect(bytes[6]).assertEqual(0);
      expect(bytes[7]).assertEqual(1);
    });

    it('counterToBytes_beyond32bit', 0, () => {
      // 666666666 = 0x27BC86AA，验证不能用 `<<` 直接拼（会 32 位溢出）。
      const bytes: Uint8Array = counterToBytes(666666666);
      expect(bytes.length).assertEqual(8);
      expect(bytes[0]).assertEqual(0);
      expect(bytes[1]).assertEqual(0);
      expect(bytes[2]).assertEqual(0);
      expect(bytes[3]).assertEqual(0);
      expect(bytes[4]).assertEqual(39);
      expect(bytes[5]).assertEqual(188);
      expect(bytes[6]).assertEqual(134);
      expect(bytes[7]).assertEqual(170);
    });

    it('counterToBytes_2pow32', 0, () => {
      const bytes: Uint8Array = counterToBytes(4294967296);
      expect(bytes.length).assertEqual(8);
      expect(bytes[0]).assertEqual(0);
      expect(bytes[1]).assertEqual(0);
      expect(bytes[2]).assertEqual(0);
      expect(bytes[3]).assertEqual(1);
      expect(bytes[4]).assertEqual(0);
      expect(bytes[5]).assertEqual(0);
      expect(bytes[6]).assertEqual(0);
      expect(bytes[7]).assertEqual(0);
    });

    it('truncate_offset15', 0, () => {
      const digest: Uint8Array = new Uint8Array(20);
      digest[19] = 0x0f; // offset = 0x0f & 0x0f = 15
      digest[15] = 0x01;
      expect(truncate(digest)).assertEqual(777216);
    });

    it('zeroPad6', 0, () => {
      expect(zeroPad6(287082)).assertEqual('287082');
      expect(zeroPad6(1234)).assertEqual('001234');
      expect(zeroPad6(0)).assertEqual('000000');
    });
  });
}
