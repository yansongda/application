/**
 * PBKDF2-HMAC-SHA256（纯函数，复用 src/otp/internal 原语）。
 *
 * 同步内核只供单测使用；运行期必须走 pbkdf2Sha256Async —— 小程序 JS 单线程，
 * 100k 迭代同步执行会把 UI 与取消按钮一起冻结，因此每约 2000 次迭代让出事件循环
 * 并回报进度（规范 §4.1 / 计划 R2）。
 */
import { hmac } from "../otp/internal/hmac";
import { sha256 } from "../otp/internal/sha256";

const BLOCK_SIZE = 64;
const HASH_BYTES = 32;
const CHUNK_ITERATIONS = 2000;

export class Pbkdf2AbortedError extends Error {
  constructor() {
    super("PBKDF2 已取消");
    this.name = "Pbkdf2AbortedError";
  }
}

export interface Pbkdf2Hooks {
  onProgress?: (done: number, total: number) => void;
  isCancelled?: () => boolean;
}

const assertParams = (
  password: Uint8Array,
  salt: Uint8Array,
  iterations: number,
  dkLen: number,
): void => {
  if (!Number.isInteger(iterations) || iterations < 1) {
    throw new Error("PBKDF2 迭代数必须为正整数");
  }

  if (!Number.isInteger(dkLen) || dkLen < 1) {
    throw new Error("PBKDF2 派生长度必须为正整数");
  }

  if (password.length === 0) {
    throw new Error("PBKDF2 口令不能为空");
  }

  if (salt.length === 0) {
    throw new Error("PBKDF2 salt 不能为空");
  }
};

// F(P, S, c, i) = U1 xor U2 ... xor Uc，U1 = HMAC(P, S || INT(i))
const deriveBlock = (
  password: Uint8Array,
  salt: Uint8Array,
  iterations: number,
  index: number,
  onIteration?: (done: number) => void,
  isCancelled?: () => boolean,
): Uint8Array => {
  const saltWithIndex = new Uint8Array(salt.length + 4);
  saltWithIndex.set(salt);
  saltWithIndex[salt.length] = (index >>> 24) & 0xff;
  saltWithIndex[salt.length + 1] = (index >>> 16) & 0xff;
  saltWithIndex[salt.length + 2] = (index >>> 8) & 0xff;
  saltWithIndex[salt.length + 3] = index & 0xff;

  let u = hmac(sha256, BLOCK_SIZE, password, saltWithIndex);
  const out = new Uint8Array(u);

  for (let i = 1; i < iterations; i++) {
    if (isCancelled?.() === true) {
      throw new Pbkdf2AbortedError();
    }

    u = hmac(sha256, BLOCK_SIZE, password, u);

    for (let j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }

    if (onIteration !== undefined && i % CHUNK_ITERATIONS === 0) {
      onIteration(i);
    }
  }

  return out;
};

/** 同步内核（仅供单测与向量断言；运行期禁止使用）。 */
export const pbkdf2Sha256 = (
  password: Uint8Array,
  salt: Uint8Array,
  iterations: number,
  dkLen: number,
): Uint8Array => {
  assertParams(password, salt, iterations, dkLen);

  const blocks = Math.ceil(dkLen / HASH_BYTES);
  const out = new Uint8Array(blocks * HASH_BYTES);

  for (let index = 1; index <= blocks; index++) {
    out.set(
      deriveBlock(password, salt, iterations, index),
      (index - 1) * HASH_BYTES,
    );
  }

  return out.subarray(0, dkLen);
};

const yieldToEventLoop = (): Promise<void> => {
  return new Promise((resolve) => {
    setTimeout(resolve, 0);
  });
};

/**
 * 分片异步派生：每约 2000 次迭代让出一次事件循环，并回报已完成迭代数。
 * isCancelled 返回 true 时抛 Pbkdf2AbortedError（调用方据此中止并提示已取消）。
 */
export const pbkdf2Sha256Async = async (
  password: Uint8Array,
  salt: Uint8Array,
  iterations: number,
  dkLen: number,
  hooks?: Pbkdf2Hooks,
): Promise<Uint8Array> => {
  assertParams(password, salt, iterations, dkLen);

  const blocks = Math.ceil(dkLen / HASH_BYTES);
  const out = new Uint8Array(blocks * HASH_BYTES);
  const onProgress = hooks?.onProgress;
  const isCancelled = hooks?.isCancelled;

  for (let index = 1; index <= blocks; index++) {
    const saltWithIndex = new Uint8Array(salt.length + 4);
    saltWithIndex.set(salt);
    saltWithIndex[salt.length] = (index >>> 24) & 0xff;
    saltWithIndex[salt.length + 1] = (index >>> 16) & 0xff;
    saltWithIndex[salt.length + 2] = (index >>> 8) & 0xff;
    saltWithIndex[salt.length + 3] = index & 0xff;

    let u = hmac(sha256, BLOCK_SIZE, password, saltWithIndex);
    const blockOut = new Uint8Array(u);

    let i = 1;

    while (i < iterations) {
      const end = Math.min(i + CHUNK_ITERATIONS, iterations);

      for (; i < end; i++) {
        u = hmac(sha256, BLOCK_SIZE, password, u);

        for (let j = 0; j < blockOut.length; j++) {
          blockOut[j] ^= u[j];
        }
      }

      onProgress?.(i, iterations);

      if (isCancelled?.() === true) {
        throw new Pbkdf2AbortedError();
      }

      if (i < iterations) {
        await yieldToEventLoop();
      }
    }

    out.set(blockOut, (index - 1) * HASH_BYTES);
  }

  return out.subarray(0, dkLen);
};
