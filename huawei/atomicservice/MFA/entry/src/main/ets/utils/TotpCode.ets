// 端内 TOTP 算码：cryptoFramework HMAC-SHA1 + 动态截断 + 6 位零填充。
// SHA1 为 RFC 6238/TOTP 互操作与后端 build_noncompliant（SHA1 + 6 位）对齐的硬性要求；
// 命中 @security/no-unsafe-mac 告警属预期，不放宽规则、不加 disable 注释。
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { base32Decode, counterToBytes, truncate, zeroPad6 } from './TotpMath';

export class TotpCode {
  static async compute(secret: string, period: number, timestamp: number): Promise<string> {
    // period 必须为正整数（config.period = 0 的账户端内不可达，此校验仅作纯防御）。
    if (!Number.isInteger(period) || !(period > 0)) {
      throw new Error('非法的 TOTP 周期');
    }
    if (!(timestamp > 0)) {
      throw new Error('非法的算码时间戳');
    }

    // base32 解码出 HMAC 密钥；计数器为当前时间窗序号（epoch 秒 / period 向下取整）。
    const key: Uint8Array = base32Decode(secret);
    const message: Uint8Array = counterToBytes(Math.floor(timestamp / 1000 / period));

    // 用通用 'HMAC' 规格导入密钥：官方支持 [1, 32768] 位、短密钥末尾补 0，
    // 兼容任意长度 secret；不得用 'HMAC|SHA1'（该规格要求密钥恰 160 位）。
    try {
      const symKeyGenerator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
      const symKey: cryptoFramework.SymKey = await symKeyGenerator.convertKey({ data: key });
      const mac: cryptoFramework.Mac = cryptoFramework.createMac('SHA1');
      await mac.init(symKey);
      await mac.update({ data: message });
      const digest: cryptoFramework.DataBlob = await mac.doFinal();

      return zeroPad6(truncate(new Uint8Array(digest.data)));
    } catch (e) {
      // 端内算码失败：本层不吞错、不打日志、不输出 secret，归一化后抛给调用方，
      // 由 Runtime.freshCode() 回落 /totp/detail 兜底。
      throw new Error('端内 TOTP 算码失败');
    }
  }
}
