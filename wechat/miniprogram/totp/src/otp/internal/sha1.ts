/**
 * FIPS 180-4 SHA-1（纯 32 位实现，无平台依赖）。
 *
 * 仅为 OTP 单块 HMAC 服务，因此不提供流式 API：一次哈希 = 一次分配 + 压缩。
 * 所有加法末尾用 | 0 收敛为 32 位，位运算天然按 32 位处理。
 */
const BLOCK_SIZE = 64;
const INIT: ReadonlyArray<number> = [
  0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0,
];

function rotl(x: number, n: number): number {
  return (x << n) | (x >>> (32 - n));
}

/** 写入 32 位大端字（避免依赖平台 Buffer）。 */
function writeBE(out: Uint8Array, offset: number, value: number): void {
  out[offset] = (value >>> 24) & 0xff;
  out[offset + 1] = (value >>> 16) & 0xff;
  out[offset + 2] = (value >>> 8) & 0xff;
  out[offset + 3] = value & 0xff;
}

export function sha1(message: Uint8Array): Uint8Array {
  // 补 1 个 0x80 + 8 字节长度，块尾对齐到 64 字节
  const paddedLength =
    Math.ceil((message.length + 9) / BLOCK_SIZE) * BLOCK_SIZE;
  const padded = new Uint8Array(paddedLength);
  padded.set(message);
  padded[message.length] = 0x80;

  // 消息长度（bit）写入末 8 字节；JS 精确整数上限内 high 恒为 0
  const bitLength = message.length * 8;
  const tail = paddedLength - 8;
  writeBE(padded, tail, Math.floor(bitLength / 2 ** 32));
  writeBE(padded, tail + 4, bitLength % 2 ** 32);

  let h0 = INIT[0];
  let h1 = INIT[1];
  let h2 = INIT[2];
  let h3 = INIT[3];
  let h4 = INIT[4];

  const w = new Int32Array(80);

  for (let block = 0; block < paddedLength; block += BLOCK_SIZE) {
    for (let i = 0; i < 16; i++) {
      const j = block + i * 4;
      w[i] =
        (padded[j] << 24) |
        (padded[j + 1] << 16) |
        (padded[j + 2] << 8) |
        padded[j + 3];
    }
    for (let i = 16; i < 80; i++) {
      w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }

    let a = h0;
    let b = h1;
    let c = h2;
    let d = h3;
    let e = h4;

    for (let i = 0; i < 80; i++) {
      let f: number;
      let k: number;
      if (i < 20) {
        f = (b & c) | (~b & d);
        k = 0x5a827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ed9eba1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8f1bbcdc;
      } else {
        f = b ^ c ^ d;
        k = 0xca62c1d6;
      }
      const temp = (rotl(a, 5) + f + e + k + w[i]) | 0;
      e = d;
      d = c;
      c = rotl(b, 30);
      b = a;
      a = temp;
    }

    const t0 = (h0 + a) | 0;
    const t1 = (h1 + b) | 0;
    const t2 = (h2 + c) | 0;
    const t3 = (h3 + d) | 0;
    const t4 = (h4 + e) | 0;
    h0 = t0; // 逐轮累加后写回，保持与 FIPS 180-4 §6.1 的链式定义一致
    h1 = t1;
    h2 = t2;
    h3 = t3;
    h4 = t4;
  }

  const digest = new Uint8Array(20);
  writeBE(digest, 0, h0);
  writeBE(digest, 4, h1);
  writeBE(digest, 8, h2);
  writeBE(digest, 12, h3);
  writeBE(digest, 16, h4);
  return digest;
}
