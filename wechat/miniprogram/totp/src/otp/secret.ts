/**
 * Secret：secret 规范化 / 校验 / 随机生成 / toJSON 脱敏（无平台依赖，随机源经 requireRandom()）。
 *
 * 刻意不实现 toString()：避免 String() / 模板字符串把密钥明文带入日志或 UI；
 * 脱敏由 toJSON() 承担 —— JSON.stringify 会调用它，而 TS 的 private 只是编译期约束。
 */
import { OtpError, OtpErrorCode } from "./errors";
import { decode, decodeStrict, encode } from "./internal/base32";
import { requireRandom } from "./internal/crypto-provider";
import type { ParseOptions } from "./options";

export class Secret {
  private readonly _bytes: Uint8Array;

  private constructor(bytes: Uint8Array) {
    this._bytes = bytes;
  }

  /**
   * 从 base32 字符串构造，默认宽松解析（容忍大小写 / 空白 / 填充）；空结果抛 EMPTY_SECRET。
   * options.strict === true 时追加规范形式校验（尾长 ∈ {0,2,4,5,7} 且填充位为 0），
   * 不合规抛 INVALID_BASE32_PADDING —— 用于「拒绝被截断 / 被改写的 secret」的导入边界。
   */
  static fromBase32(input: string, options?: ParseOptions): Secret {
    const strict = options !== undefined && options.strict === true;
    const bytes = strict ? decodeStrict(input) : decode(input);
    if (bytes.length === 0) {
      throw new OtpError(OtpErrorCode.EMPTY_SECRET, "EMPTY_SECRET");
    }
    return new Secret(bytes);
  }

  /** 从字节数组构造（拷贝入参，杜绝外部引用共享）；空数组抛 EMPTY_SECRET。 */
  static fromBytes(bytes: Uint8Array): Secret {
    if (bytes.length === 0) {
      throw new OtpError(OtpErrorCode.EMPTY_SECRET, "EMPTY_SECRET");
    }
    return new Secret(new Uint8Array(bytes));
  }

  /**
   * 随机生成 bytes 字节 secret（默认 20 字节 = RFC 4226 推荐 160 bit）。
   * bytes 须为 [1, 4096] 整数，否则抛 SECRET_TOO_WEAK（与内部随机源的边界同一错误码）。
   *
   * 注意：微信小程序默认不注册随机源（wx.getRandomValues 异步），
   * 未注入 RandomSource 时本方法抛 CRYPTO_NOT_INITIALIZED。
   */
  static generate(bytes = 20): Secret {
    if (!Number.isInteger(bytes) || bytes < 1 || bytes > 4096) {
      throw new OtpError(OtpErrorCode.SECRET_TOO_WEAK, "SECRET_TOO_WEAK");
    }
    return new Secret(new Uint8Array(requireRandom().random(bytes)));
  }

  /** 字节视图：返回拷贝，外部改动不影响内部。 */
  get bytes(): Uint8Array {
    return new Uint8Array(this._bytes);
  }

  get byteLength(): number {
    return this._bytes.length;
  }

  get bitLength(): number {
    return this._bytes.length * 8;
  }

  /** 规范化输出：大写、无填充 base32。 */
  toBase32(): string {
    return encode(this._bytes);
  }

  /** 序列化脱敏：JSON.stringify 会调用本方法，固定返回 '[REDACTED]'，不泄漏密钥。 */
  toJSON(): string {
    return "[REDACTED]";
  }
}
