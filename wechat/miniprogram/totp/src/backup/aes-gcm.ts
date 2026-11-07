/**
 * AES-256-GCM（手写，零依赖，不使用大整数类型）。
 *
 * 仅供 MFA 加密备份使用：仅实现 GCM 所需的 AES 加密方向（CTR 与 GHASH 都用加密），
 * 因此不实现 AES 解密轮函数。IV 固定 12 字节、tag 固定 16 字节（规范 §4.1）。
 * 正确性由 docs/specs/mfa-backup-v1.vectors.json 的共享向量保证。
 */

const SBOX: ReadonlyArray<number> = [
  0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe,
  0xd7, 0xab, 0x76, 0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4,
  0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0, 0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7,
  0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15, 0x04, 0xc7, 0x23, 0xc3,
  0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75, 0x09,
  0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3,
  0x2f, 0x84, 0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe,
  0x39, 0x4a, 0x4c, 0x58, 0xcf, 0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85,
  0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8, 0x51, 0xa3, 0x40, 0x8f, 0x92,
  0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2, 0xcd, 0x0c,
  0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19,
  0x73, 0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14,
  0xde, 0x5e, 0x0b, 0xdb, 0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2,
  0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79, 0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5,
  0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08, 0xba, 0x78, 0x25,
  0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
  0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86,
  0xc1, 0x1d, 0x9e, 0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e,
  0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf, 0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42,
  0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
];

const RCON: ReadonlyArray<number> = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40];

const BLOCK_BYTES = 16;
const KEY_BYTES = 32;
const NR = 14;

/** AES-256 密钥扩展：60 个 32 位字。 */
const expandKey = (key: Uint8Array): Uint32Array => {
  if (key.length !== KEY_BYTES) {
    throw new Error("AES-256 密钥必须为 32 字节");
  }

  const words = new Uint32Array(4 * (NR + 1));

  for (let i = 0; i < 8; i++) {
    words[i] =
      ((key[4 * i] << 24) |
        (key[4 * i + 1] << 16) |
        (key[4 * i + 2] << 8) |
        key[4 * i + 3]) >>>
      0;
  }

  for (let i = 8; i < words.length; i++) {
    let temp = words[i - 1];

    if (i % 8 === 0) {
      // RotWord + SubWord + Rcon
      temp =
        ((SBOX[(temp >>> 16) & 0xff] << 24) |
          (SBOX[(temp >>> 8) & 0xff] << 16) |
          (SBOX[temp & 0xff] << 8) |
          SBOX[(temp >>> 24) & 0xff]) >>>
        0;
      temp ^= RCON[i / 8 - 1] << 24;
    } else if (i % 8 === 4) {
      temp =
        ((SBOX[(temp >>> 24) & 0xff] << 24) |
          (SBOX[(temp >>> 16) & 0xff] << 16) |
          (SBOX[(temp >>> 8) & 0xff] << 8) |
          SBOX[temp & 0xff]) >>>
        0;
    }

    words[i] = (words[i - 8] ^ temp) >>> 0;
  }

  return words;
};

const xtime = (value: number): number => {
  return ((value << 1) ^ (value & 0x80 ? 0x1b : 0)) & 0xff;
};

const mul3 = (value: number): number => {
  return xtime(value) ^ value;
};

const subBytes = (state: Uint8Array): void => {
  for (let i = 0; i < BLOCK_BYTES; i++) {
    state[i] = SBOX[state[i]];
  }
};

// 行位移：state[r][c] = state[r][c + r]（列优先索引 = r + 4c）
const shiftRows = (state: Uint8Array): void => {
  const copy = new Uint8Array(state);
  for (let r = 1; r < 4; r++) {
    for (let c = 0; c < 4; c++) {
      state[r + 4 * c] = copy[r + 4 * ((c + r) % 4)];
    }
  }
};

const mixColumns = (state: Uint8Array): void => {
  for (let c = 0; c < 4; c++) {
    const i = 4 * c;
    const a0 = state[i];
    const a1 = state[i + 1];
    const a2 = state[i + 2];
    const a3 = state[i + 3];

    state[i] = xtime(a0) ^ mul3(a1) ^ a2 ^ a3;
    state[i + 1] = a0 ^ xtime(a1) ^ mul3(a2) ^ a3;
    state[i + 2] = a0 ^ a1 ^ xtime(a2) ^ mul3(a3);
    state[i + 3] = mul3(a0) ^ a1 ^ a2 ^ xtime(a3);
  }
};

const addRoundKey = (
  state: Uint8Array,
  roundKeys: Uint32Array,
  round: number,
): void => {
  for (let c = 0; c < 4; c++) {
    const word = roundKeys[round * 4 + c];
    const i = 4 * c;
    state[i] ^= (word >>> 24) & 0xff;
    state[i + 1] ^= (word >>> 16) & 0xff;
    state[i + 2] ^= (word >>> 8) & 0xff;
    state[i + 3] ^= word & 0xff;
  }
};

/** 单块 AES-256 加密（原地修改 state）。 */
const encryptBlock = (state: Uint8Array, roundKeys: Uint32Array): void => {
  addRoundKey(state, roundKeys, 0);

  for (let round = 1; round < NR; round++) {
    subBytes(state);
    shiftRows(state);
    mixColumns(state);
    addRoundKey(state, roundKeys, round);
  }

  subBytes(state);
  shiftRows(state);
  addRoundKey(state, roundKeys, NR);
};

const blockFromBytes = (
  bytes: Uint8Array,
  offset: number,
  fill: number,
): Uint8Array => {
  const block = new Uint8Array(BLOCK_BYTES).fill(fill);
  const end = Math.min(offset + BLOCK_BYTES, bytes.length);
  block.set(bytes.subarray(offset, end));
  return block;
};

// GHASH 的 128 位状态：4 个 32 位字，大端（index 0 为最高 32 位）
const xorWords = (target: Uint32Array, source: Uint32Array): void => {
  target[0] ^= source[0];
  target[1] ^= source[1];
  target[2] ^= source[2];
  target[3] ^= source[3];
};

const wordsFromBlock = (block: Uint8Array): Uint32Array => {
  return new Uint32Array([
    ((block[0] << 24) | (block[1] << 16) | (block[2] << 8) | block[3]) >>> 0,
    ((block[4] << 24) | (block[5] << 16) | (block[6] << 8) | block[7]) >>> 0,
    ((block[8] << 24) | (block[9] << 16) | (block[10] << 8) | block[11]) >>> 0,
    ((block[12] << 24) | (block[13] << 16) | (block[14] << 8) | block[15]) >>>
      0,
  ]);
};

/** GF(2^128) 乘法：reduce 多项式 x^128 + x^7 + x^2 + x + 1（R = 0xe1 << 120）。 */
const gfMultiply = (x: Uint32Array, h: Uint32Array): Uint32Array => {
  const z = new Uint32Array(4);
  const v = new Uint32Array(4);
  v.set(h);

  for (let i = 0; i < 128; i++) {
    const bit = (x[i >>> 5] >>> (31 - (i & 31))) & 1;

    if (bit === 1) {
      z[0] ^= v[0];
      z[1] ^= v[1];
      z[2] ^= v[2];
      z[3] ^= v[3];
    }

    const lsb = v[3] & 1;
    v[3] = (v[3] >>> 1) | ((v[2] & 1) << 31);
    v[2] = (v[2] >>> 1) | ((v[1] & 1) << 31);
    v[1] = (v[1] >>> 1) | ((v[0] & 1) << 31);
    v[0] = v[0] >>> 1;

    if (lsb === 1) {
      v[0] ^= 0xe1000000;
    }
  }

  return z;
};

const ghash = (
  h: Uint32Array,
  aad: Uint8Array,
  ciphertext: Uint8Array,
): Uint8Array => {
  let y: Uint32Array = new Uint32Array(4);

  const absorb = (bytes: Uint8Array): void => {
    for (let offset = 0; offset < bytes.length; offset += BLOCK_BYTES) {
      const block = blockFromBytes(bytes, offset, 0);
      xorWords(y, wordsFromBlock(block));
      y = gfMultiply(y, h);
    }
  };

  absorb(aad);
  absorb(ciphertext);

  // 长度块：len(AAD) || len(CT)，单位 bit，各 64 位大端
  const lengthBlock = new Uint8Array(BLOCK_BYTES);
  const aadBits = aad.length * 8;
  const ctBits = ciphertext.length * 8;
  const write64 = (value: number, offset: number): void => {
    const high = Math.floor(value / 2 ** 32);
    const low = value % 2 ** 32;
    lengthBlock[offset] = (high >>> 24) & 0xff;
    lengthBlock[offset + 1] = (high >>> 16) & 0xff;
    lengthBlock[offset + 2] = (high >>> 8) & 0xff;
    lengthBlock[offset + 3] = high & 0xff;
    lengthBlock[offset + 4] = (low >>> 24) & 0xff;
    lengthBlock[offset + 5] = (low >>> 16) & 0xff;
    lengthBlock[offset + 6] = (low >>> 8) & 0xff;
    lengthBlock[offset + 7] = low & 0xff;
  };
  write64(aadBits, 0);
  write64(ctBits, 8);

  xorWords(y, wordsFromBlock(lengthBlock));
  y = gfMultiply(y, h);

  const out = new Uint8Array(BLOCK_BYTES);

  for (let i = 0; i < 4; i++) {
    out[4 * i] = (y[i] >>> 24) & 0xff;
    out[4 * i + 1] = (y[i] >>> 16) & 0xff;
    out[4 * i + 2] = (y[i] >>> 8) & 0xff;
    out[4 * i + 3] = y[i] & 0xff;
  }

  return out;
};

const inc32 = (block: Uint8Array, value: number): Uint8Array => {
  const out = new Uint8Array(block);
  let carry = value;

  for (let i = BLOCK_BYTES - 1; i >= BLOCK_BYTES - 4; i--) {
    const sum = out[i] + (carry & 0xff);
    out[i] = sum & 0xff;
    carry = (carry >>> 8) + (sum >>> 8);
  }

  return out;
};

const ctrCrypt = (
  roundKeys: Uint32Array,
  j0: Uint8Array,
  input: Uint8Array,
): Uint8Array => {
  const out = new Uint8Array(input.length);

  for (let offset = 0; offset < input.length; offset += BLOCK_BYTES) {
    const counter = inc32(j0, offset / BLOCK_BYTES + 1);
    encryptBlock(counter, roundKeys);
    const end = Math.min(offset + BLOCK_BYTES, input.length);

    for (let i = offset; i < end; i++) {
      out[i] = input[i] ^ counter[i - offset];
    }
  }

  return out;
};

const constantTimeEqual = (a: Uint8Array, b: Uint8Array): boolean => {
  if (a.length !== b.length) {
    return false;
  }

  let diff = 0;

  for (let i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }

  return diff === 0;
};

const assertIvAndKey = (key: Uint8Array, iv: Uint8Array): void => {
  if (key.length !== KEY_BYTES) {
    throw new Error("AES-256 密钥必须为 32 字节");
  }

  if (iv.length !== 12) {
    throw new Error("GCM IV 必须为 12 字节");
  }
};

export interface AesGcmResult {
  ciphertext: Uint8Array;
  tag: Uint8Array;
}

/** AES-256-GCM 加密；返回密文与 16 字节 tag。 */
export const aesGcmEncrypt = (
  key: Uint8Array,
  iv: Uint8Array,
  aad: Uint8Array,
  plaintext: Uint8Array,
): AesGcmResult => {
  assertIvAndKey(key, iv);

  const roundKeys = expandKey(key);
  const h = new Uint8Array(BLOCK_BYTES);
  encryptBlock(h, roundKeys);

  const j0 = new Uint8Array(BLOCK_BYTES);
  j0.set(iv);
  j0[BLOCK_BYTES - 1] = 1;

  const ciphertext = ctrCrypt(roundKeys, j0, plaintext);
  const s = ghash(wordsFromBlock(h), aad, ciphertext);

  const j0Block = new Uint8Array(j0);
  encryptBlock(j0Block, roundKeys);

  const tag = new Uint8Array(BLOCK_BYTES);

  for (let i = 0; i < BLOCK_BYTES; i++) {
    tag[i] = s[i] ^ j0Block[i];
  }

  return { ciphertext, tag };
};

/** AES-256-GCM 解密；tag 不匹配返回 null（由调用方映射 E_CORRUPT）。 */
export const aesGcmDecrypt = (
  key: Uint8Array,
  iv: Uint8Array,
  aad: Uint8Array,
  ciphertext: Uint8Array,
  tag: Uint8Array,
): Uint8Array | null => {
  assertIvAndKey(key, iv);

  if (tag.length !== 16) {
    throw new Error("GCM tag 必须为 16 字节");
  }

  const roundKeys = expandKey(key);
  const h = new Uint8Array(BLOCK_BYTES);
  encryptBlock(h, roundKeys);

  const j0 = new Uint8Array(BLOCK_BYTES);
  j0.set(iv);
  j0[BLOCK_BYTES - 1] = 1;

  const s = ghash(wordsFromBlock(h), aad, ciphertext);

  const j0Block = new Uint8Array(j0);
  encryptBlock(j0Block, roundKeys);

  const expected = new Uint8Array(BLOCK_BYTES);

  for (let i = 0; i < BLOCK_BYTES; i++) {
    expected[i] = s[i] ^ j0Block[i];
  }

  if (!constantTimeEqual(expected, tag)) {
    return null;
  }

  return ctrCrypt(roundKeys, j0, ciphertext);
};
