/**
 * FIPS 180-4 SHA-512（纯 32 位 hi/lo 实现，无 BigInt、无平台依赖）。
 *
 * 为什么不用 BigInt：部分老设备/老基础库的 JS 引擎缺少 BigInt，
 * 且本库与 ohos-otp 一致要求「大整数一律 high/low 拆分」。
 * 本轮常量取自 RFC 6234 §5.2（前 80 个素数立方根小数部分的前 64 位），
 * 以 32 位半字拆分存储，避免运行期 BigInt 解析。
 *
 * 仅为 OTP 单块 HMAC 服务，不提供流式 API。
 */
const BLOCK_SIZE = 128;

const INIT_HI: ReadonlyArray<number> = [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
  0x1f83d9ab, 0x5be0cd19,
];
const INIT_LO: ReadonlyArray<number> = [
  0xf3bcc908, 0x84caa73b, 0xfe94f82b, 0x5f1d36f1, 0xade682d1, 0x2b3e6c1f,
  0xfb41bd6b, 0x137e2179,
];

// RFC 6234 §5.2 的 80 个 64 位轮常量，按下标拆为高/低 32 位
const K_HI: ReadonlyArray<number> = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2, 0xca273ece, 0xd186b8c7,
  0xeada7dd6, 0xf57d4f7f, 0x06f067aa, 0x0a637dc5, 0x113f9804, 0x1b710b35,
  0x28db77f5, 0x32caab7b, 0x3c9ebe0a, 0x431d67c4, 0x4cc5d4be, 0x597f299c,
  0x5fcb6fab, 0x6c44198c,
];
const K_LO: ReadonlyArray<number> = [
  0xd728ae22, 0x23ef65cd, 0xec4d3b2f, 0x8189dbbc, 0xf348b538, 0xb605d019,
  0xaf194f9b, 0xda6d8118, 0xa3030242, 0x45706fbe, 0x4ee4b28c, 0xd5ffb4e2,
  0xf27b896f, 0x3b1696b1, 0x25c71235, 0xcf692694, 0x9ef14ad2, 0x384f25e3,
  0x8b8cd5b5, 0x77ac9c65, 0x592b0275, 0x6ea6e483, 0xbd41fbd4, 0x831153b5,
  0xee66dfab, 0x2db43210, 0x98fb213f, 0xbeef0ee4, 0x3da88fc2, 0x930aa725,
  0xe003826f, 0x0a0e6e70, 0x46d22ffc, 0x5c26c926, 0x5ac42aed, 0x9d95b3df,
  0x8baf63de, 0x3c77b2a8, 0x47edaee6, 0x1482353b, 0x4cf10364, 0xbc423001,
  0xd0f89791, 0x0654be30, 0xd6ef5218, 0x5565a910, 0x5771202a, 0x32bbd1b8,
  0xb8d2d0c8, 0x5141ab53, 0xdf8eeb99, 0xe19b48a8, 0xc5c95a63, 0xe3418acb,
  0x7763e373, 0xd6b2b8a3, 0x5defb2fc, 0x43172f60, 0xa1f0ab72, 0x1a6439ec,
  0x23631e28, 0xde82bde9, 0xb2c67915, 0xe372532b, 0xea26619c, 0x21c0c207,
  0xcde0eb1e, 0xee6ed178, 0x72176fba, 0xa2c898a6, 0xbef90dae, 0x131c471b,
  0x23047d84, 0x40c72493, 0x15c9bebc, 0x9c100d4c, 0xcb3e42b6, 0xfc657e2a,
  0x3ad6faec, 0x4a475817,
];

/** 64 位右旋：返回 [hi, lo]。n ∈ [1, 63]，不含 0/32 的未定义移位。 */
function rotr64(hi: number, lo: number, n: number): [number, number] {
  if (n < 32) {
    return [
      ((hi >>> n) | (lo << (32 - n))) >>> 0,
      ((lo >>> n) | (hi << (32 - n))) >>> 0,
    ];
  }
  const m = n - 32;
  return [
    ((lo >>> m) | (hi << (32 - m))) >>> 0,
    ((hi >>> m) | (lo << (32 - m))) >>> 0,
  ];
}

/** 64 位右移：返回 [hi, lo]。 */
function shr64(hi: number, lo: number, n: number): [number, number] {
  if (n < 32) {
    return [hi >>> n, ((lo >>> n) | (hi << (32 - n))) >>> 0];
  }
  return [0, hi >>> (n - 32)];
}

/** 64 位加法（模 2^64）：入参两个半字须为无符号 32 位值。 */
function add64(
  h1: number,
  l1: number,
  h2: number,
  l2: number,
): [number, number] {
  const lo = (l1 + l2) >>> 0;
  // (l1 + l2) 超过 2^32 时 lo 回绕，表现为 lo < l1；此时向高位进 1
  const carry = lo < l1 ? 1 : 0;
  return [(h1 + h2 + carry) >>> 0, lo];
}

/** 三个 64 位值异或：返回 [hi, lo]。 */
function xor3(
  a: [number, number],
  b: [number, number],
  c: [number, number],
): [number, number] {
  return [(a[0] ^ b[0] ^ c[0]) >>> 0, (a[1] ^ b[1] ^ c[1]) >>> 0];
}

function writeBE(out: Uint8Array, offset: number, value: number): void {
  out[offset] = (value >>> 24) & 0xff;
  out[offset + 1] = (value >>> 16) & 0xff;
  out[offset + 2] = (value >>> 8) & 0xff;
  out[offset + 3] = value & 0xff;
}

export function sha512(message: Uint8Array): Uint8Array {
  // 128 字节块：补 0x80 + 16 字节长度；padding 必须留出至少 17 字节
  const paddedLength =
    Math.ceil((message.length + 17) / BLOCK_SIZE) * BLOCK_SIZE;
  const padded = new Uint8Array(paddedLength);
  padded.set(message);
  padded[message.length] = 0x80;

  // 128 位长度：高 64 位在实践输入范围内恒为 0，低 64 位拆成高低 32 位写入
  const bitLength = message.length * 8;
  writeBE(padded, paddedLength - 8, Math.floor(bitLength / 2 ** 32));
  writeBE(padded, paddedLength - 4, bitLength % 2 ** 32);

  const h = new Uint32Array(8);
  const l = new Uint32Array(8);
  h.set(INIT_HI);
  l.set(INIT_LO);

  const wh = new Uint32Array(80);
  const wl = new Uint32Array(80);

  for (let block = 0; block < paddedLength; block += BLOCK_SIZE) {
    for (let i = 0; i < 16; i++) {
      const j = block + i * 8;
      wh[i] =
        (padded[j] << 24) |
        (padded[j + 1] << 16) |
        (padded[j + 2] << 8) |
        padded[j + 3];
      wl[i] =
        (padded[j + 4] << 24) |
        (padded[j + 5] << 16) |
        (padded[j + 6] << 8) |
        padded[j + 7];
    }
    for (let i = 16; i < 80; i++) {
      // σ1(W[i-2]) = ROTR19 ^ ROTR61 ^ SHR6
      const s1 = xor3(
        rotr64(wh[i - 2], wl[i - 2], 19),
        rotr64(wh[i - 2], wl[i - 2], 61),
        shr64(wh[i - 2], wl[i - 2], 6),
      );
      // σ0(W[i-15]) = ROTR1 ^ ROTR8 ^ SHR7
      const s0 = xor3(
        rotr64(wh[i - 15], wl[i - 15], 1),
        rotr64(wh[i - 15], wl[i - 15], 8),
        shr64(wh[i - 15], wl[i - 15], 7),
      );
      const [x1h, x1l] = add64(s1[0], s1[1], wh[i - 7], wl[i - 7]);
      const [x2h, x2l] = add64(s0[0], s0[1], wh[i - 16], wl[i - 16]);
      const [wih, wil] = add64(x1h, x1l, x2h, x2l);
      wh[i] = wih;
      wl[i] = wil;
    }

    let ah = h[0];
    let al = l[0];
    let bh = h[1];
    let bl = l[1];
    let c1h = h[2];
    let c1l = l[2];
    let dh = h[3];
    let dl = l[3];
    let eh = h[4];
    let el = l[4];
    let fh = h[5];
    let fl = l[5];
    let gh = h[6];
    let gl = l[6];
    let hh = h[7];
    let hl = l[7];

    for (let i = 0; i < 80; i++) {
      // Σ1(e) = ROTR14 ^ ROTR18 ^ ROTR41
      const sigma1 = xor3(
        rotr64(eh, el, 14),
        rotr64(eh, el, 18),
        rotr64(eh, el, 41),
      );
      const chh = ((eh & fh) ^ (~eh & gh)) >>> 0;
      const chl = ((el & fl) ^ (~el & gl)) >>> 0;
      // Σ0(a) = ROTR28 ^ ROTR34 ^ ROTR39
      const sigma0 = xor3(
        rotr64(ah, al, 28),
        rotr64(ah, al, 34),
        rotr64(ah, al, 39),
      );
      const majh = ((ah & bh) ^ (ah & c1h) ^ (bh & c1h)) >>> 0;
      const majl = ((al & bl) ^ (al & c1l) ^ (bl & c1l)) >>> 0;

      const [p1h, p1l] = add64(hh, hl, sigma1[0], sigma1[1]);
      const [p2h, p2l] = add64(p1h, p1l, chh, chl);
      const [p3h, p3l] = add64(p2h, p2l, K_HI[i], K_LO[i]);
      const [t1h, t1l] = add64(p3h, p3l, wh[i], wl[i]);
      const [t2h, t2l] = add64(sigma0[0], sigma0[1], majh, majl);
      const [ehNew, elNew] = add64(dh, dl, t1h, t1l);
      const [ahNew, alNew] = add64(t1h, t1l, t2h, t2l);

      hh = gh;
      hl = gl;
      gh = fh;
      gl = fl;
      fh = eh;
      fl = el;
      eh = ehNew;
      el = elNew;
      dh = c1h;
      dl = c1l;
      c1h = bh;
      c1l = bl;
      bh = ah;
      bl = al;
      ah = ahNew;
      al = alNew;
    }

    const [s0h, s0l] = add64(h[0], l[0], ah, al);
    const [s1h, s1l] = add64(h[1], l[1], bh, bl);
    const [s2h, s2l] = add64(h[2], l[2], c1h, c1l);
    const [s3h, s3l] = add64(h[3], l[3], dh, dl);
    const [s4h, s4l] = add64(h[4], l[4], eh, el);
    const [s5h, s5l] = add64(h[5], l[5], fh, fl);
    const [s6h, s6l] = add64(h[6], l[6], gh, gl);
    const [s7h, s7l] = add64(h[7], l[7], hh, hl);
    h[0] = s0h;
    l[0] = s0l;
    h[1] = s1h;
    l[1] = s1l;
    h[2] = s2h;
    l[2] = s2l;
    h[3] = s3h;
    l[3] = s3l;
    h[4] = s4h;
    l[4] = s4l;
    h[5] = s5h;
    l[5] = s5l;
    h[6] = s6h;
    l[6] = s6l;
    h[7] = s7h;
    l[7] = s7l;
  }

  const digest = new Uint8Array(64);
  for (let i = 0; i < 8; i++) {
    writeBE(digest, i * 8, h[i]);
    writeBE(digest, i * 8 + 4, l[i]);
  }
  return digest;
}
