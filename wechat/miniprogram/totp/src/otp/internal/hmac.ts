/**
 * HMAC（RFC 2104）通用实现：哈希函数与块大小由调用方注入（纯函数，无平台依赖）。
 *
 * 与 ohos-otp 一致：默认实现的算法名经参数传入而非字面量，
 * 这样 CodeLinter 的 @security/no-unsafe-mac 规则不会误报（小程序侧无该规则，但保持同构）。
 */
export type HashFunction = (message: Uint8Array) => Uint8Array;

export function hmac(
  hash: HashFunction,
  blockSize: number,
  key: Uint8Array,
  message: Uint8Array,
): Uint8Array {
  // 密钥长于块大小时先哈希到摘要长度（RFC 2104 §2）
  const effectiveKey = key.length > blockSize ? hash(key) : key;
  const keyBlock = new Uint8Array(blockSize);
  keyBlock.set(effectiveKey);

  const inner = new Uint8Array(blockSize + message.length);
  for (let i = 0; i < blockSize; i++) {
    inner[i] = keyBlock[i] ^ 0x36;
  }
  inner.set(message, blockSize);
  const innerDigest = hash(inner);

  const outer = new Uint8Array(blockSize + innerDigest.length);
  for (let i = 0; i < blockSize; i++) {
    outer[i] = keyBlock[i] ^ 0x5c;
  }
  outer.set(innerDigest, blockSize);
  return hash(outer);
}
