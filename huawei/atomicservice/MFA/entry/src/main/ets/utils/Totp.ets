// TOTP 端内算码：base32 解码（RFC 4648 无填充）/ 计数器打包 / HMAC-SHA1 / 动态截断 / 6 位零填充，
// 并提供 TotpCode.compute 端内算码入口（cryptoFramework HMAC-SHA1）。
// SHA1 为 RFC 6238/TOTP 互操作与后端 build_noncompliant（SHA1 + 6 位）对齐的硬性要求；
// 命中 @security/no-unsafe-mac 告警属预期，不放宽规则、不加 disable 注释。
// 本文件顶层导入了系统 kit（CryptoArchitectureKit），因此 entry/src/test 的本地单测
// 加载本文件时可能需要系统 kit。
// 算法语义与 RFC 4226/6238、后端 build_noncompliant（SHA1 + 6 位）及微信端实现一致。
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const BASE32_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

// base32 解码（RFC 4648 无填充规则）。
// 规则：去掉所有空白、去掉尾部 '=' 填充、统一转大写；空串 / 结果为空 / 含非法字符都抛错。
// 实现：按 8 字符一组（组宽 5 字节），缺位补 0，逐位拼接；输出长度 floor(长度 * 5 / 8)。
export function base32Decode(secret: string): Uint8Array {
  const normalized: string = secret.replace(/\s/g, '').replace(/=+$/, '').toUpperCase();

  if (0 === normalized.length) {
    throw new Error('TOTP secret 为空');
  }

  // 非法字符校验：base32 字母表为 A-Z 与 2-7。
  for (let i = 0; i < normalized.length; i++) {
    if (-1 === BASE32_ALPHABET.indexOf(normalized.charAt(i))) {
      throw new Error('TOTP secret 含非法字符');
    }
  }

  // 输出长度：每 8 个字符解出 5 字节，末组按剩余有效位截断。
  const length: number = Math.floor(normalized.length * 5 / 8);
  if (0 === length) {
    throw new Error('TOTP secret 长度不足');
  }

  const result: Uint8Array = new Uint8Array(length);
  let outIndex: number = 0;

  // 按 8 字符一组解码，每组至多产出 5 字节。
  for (let start = 0; start < normalized.length; start += 8) {
    const end: number = Math.min(start + 8, normalized.length);
    const groupLength: number = end - start;

    // 把组内字符映射为 5 位数值，不足 8 个的缺位补 0。
    const buf: number[] = [];
    for (let i = start; i < end; i++) {
      buf.push(BASE32_ALPHABET.indexOf(normalized.charAt(i)));
    }
    for (let i = 0; i < 8 - groupLength; i++) {
      buf.push(0);
    }

    // 该组可解码出的字节数。
    const bytesInGroup: number = Math.floor(groupLength * 5 / 8);

    // 按 RFC 4648 的位拼接规则解出 5 字节，每字节 & 0xff 收敛为无符号字节。
    if (bytesInGroup >= 1) {
      result[outIndex] = (buf[0] << 3 | buf[1] >> 2) & 0xff;
    }
    if (bytesInGroup >= 2) {
      result[outIndex + 1] = (buf[1] << 6 | buf[2] << 1 | buf[3] >> 4) & 0xff;
    }
    if (bytesInGroup >= 3) {
      result[outIndex + 2] = (buf[3] << 4 | buf[4] >> 1) & 0xff;
    }
    if (bytesInGroup >= 4) {
      result[outIndex + 3] = (buf[4] << 7 | buf[5] << 2 | buf[6] >> 3) & 0xff;
    }
    if (bytesInGroup >= 5) {
      result[outIndex + 4] = (buf[6] << 5 | buf[7]) & 0xff;
    }
    outIndex += bytesInGroup;
  }

  return result;
}

// 把 TOTP 计数器打包为 8 字节大端。
// 说明：不能用 `<<` 直接拼 32 位——JS/ArkTS 位运算按 32 位有符号整数处理，
// 计数器可超过 32 位（如 T=20000000000 / period=30 → counter=666666666，
// 更极端时甚至超过 2^32），直接左移会溢出截断。因此拆 high/low 各 4 字节，
// 用无符号右移 >>> 与 & 0xff 逐字节取出。
export function counterToBytes(counter: number): Uint8Array {
  const high: number = Math.floor(counter / 4294967296);
  const low: number = counter % 4294967296;

  const result: Uint8Array = new Uint8Array(8);
  result[0] = (high >>> 24) & 0xff;
  result[1] = (high >>> 16) & 0xff;
  result[2] = (high >>> 8) & 0xff;
  result[3] = (high >>> 0) & 0xff;
  result[4] = (low >>> 24) & 0xff;
  result[5] = (low >>> 16) & 0xff;
  result[6] = (low >>> 8) & 0xff;
  result[7] = (low >>> 0) & 0xff;
  return result;
}

// RFC 4226 动态截断：取摘要末字节的低 4 位作偏移，从该偏移取 4 字节拼 31 位整数，再模 10^6。
export function truncate(digest: Uint8Array): number {
  if (digest.length < 20) {
    throw new Error('摘要长度不足');
  }

  const offset: number = digest[digest.length - 1] & 0x0f;
  // & 0x7f 清掉最高位，保证结果为 31 位非负整数。
  const v: number = ((digest[offset] & 0x7f) << 24)
    | (digest[offset + 1] << 16)
    | (digest[offset + 2] << 8)
    | digest[offset + 3];

  return v % 1000000;
}

// 6 位零填充（不依赖 padStart，规避 ArkTS 兼容性不确定性）。
export function zeroPad6(value: number): string {
  let text: string = String(value);
  while (text.length < 6) {
    text = '0' + text;
  }
  return text;
}

// 端内 TOTP 算码：cryptoFramework HMAC-SHA1 + 动态截断 + 6 位零填充。
// SHA1 为 RFC 6238/TOTP 互操作与后端 build_noncompliant（SHA1 + 6 位）对齐的硬性要求；
// 命中 @security/no-unsafe-mac 告警属预期，不放宽规则、不加 disable 注释。
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
      // 由 ItemRuntime.freshCode() 回落 /totp/detail 兜底。
      throw new Error('端内 TOTP 算码失败');
    }
  }
}
