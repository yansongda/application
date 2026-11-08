/**
 * 备份加解密编排：口令规范化 → PBKDF2 → kcv → AES-256-GCM → payload 校验。
 * 判定顺序严格按规范 §4.4 / §8（kcv 先于 GCM，避免把口令错误误报为文件损坏）。
 * 纯逻辑模块：随机源由调用方注入（页面经 utils/backup-file.ts 提供 wx.getRandomValues）。
 */
import { hmac } from "../otp/internal/hmac";
import { sha256 } from "../otp/internal/sha256";
import { aesGcmDecrypt, aesGcmEncrypt } from "./aes-gcm";
import { decodeBase64Strict, encodeBase64 } from "./base64";
import { type Envelope, stringifyEnvelope } from "./envelope";
import {
  type BackupItem,
  type InvalidItem,
  parsePayload,
  stringifyPayload,
} from "./payload";
import { type Pbkdf2Hooks, pbkdf2Sha256Async } from "./pbkdf2";
import {
  AAD,
  BackupError,
  BackupErrorCode,
  DEFAULT_ITERATIONS,
  IV_BYTES,
  KCV_BYTES,
  KCV_LABEL,
  KEY_BYTES,
  MAX_ITEMS,
  MIN_PASSWORD_CODE_POINTS,
  SALT_BYTES,
  VERSION,
  WEAK_PASSWORDS,
} from "./spec";

const BLOCK_SIZE = 64;

export type RandomBytes = (length: number) => Promise<Uint8Array>;

export interface EncryptContext {
  source: "huawei" | "wechat";
  app: string;
  rng: RandomBytes;
  iterations?: number;
  now?: () => Date;
}

export interface EncryptResult {
  text: string;
  envelope: Envelope;
}

export type PasswordStrength = { ok: true } | { ok: false; reason: string };

/** 口令规范化（规范 §5）：trim → NFC；运行时缺少 normalize 必须 fail-closed。 */
export const normalizePassword = (password: string): string => {
  if (typeof String.prototype.normalize !== "function") {
    throw new BackupError({
      code: BackupErrorCode.E_NORMALIZE,
      detail: "String.prototype.normalize 不可用",
    });
  }

  return password.trim().normalize("NFC");
};

/** UTF-8 编码（小程序无官方 TextEncoder，手写并正确处理代理对）。 */
export const utf8ToBytes = (text: string): Uint8Array => {
  const bytes: number[] = [];

  for (let i = 0; i < text.length; i++) {
    let code = text.charCodeAt(i);

    if (code >= 0xd800 && code <= 0xdbff) {
      const next = text.charCodeAt(i + 1);

      if (next >= 0xdc00 && next <= 0xdfff) {
        code = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
        i++;
      }
    }

    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xc0 | (code >>> 6), 0x80 | (code & 0x3f));
    } else if (code < 0x10000) {
      bytes.push(
        0xe0 | (code >>> 12),
        0x80 | ((code >>> 6) & 0x3f),
        0x80 | (code & 0x3f),
      );
    } else {
      bytes.push(
        0xf0 | (code >>> 18),
        0x80 | ((code >>> 12) & 0x3f),
        0x80 | ((code >>> 6) & 0x3f),
        0x80 | (code & 0x3f),
      );
    }
  }

  return Uint8Array.from(bytes);
};

/** 导出端强度：≥8 个 Unicode 码点、且不在弱口令表（规范 §5）。 */
export const checkPasswordStrength = (password: string): PasswordStrength => {
  const normalized = normalizePassword(password);
  const codePoints = Array.from(normalized);

  if (codePoints.length < MIN_PASSWORD_CODE_POINTS) {
    return { ok: false, reason: `口令至少 ${MIN_PASSWORD_CODE_POINTS} 个字符` };
  }

  if (WEAK_PASSWORDS.includes(normalized)) {
    return { ok: false, reason: "口令过弱，请换一个" };
  }

  return { ok: true };
};

export interface DeriveResult {
  key: Uint8Array;
  kcv: Uint8Array;
}

const deriveKey = async (
  password: string,
  salt: Uint8Array,
  iterations: number,
  hooks?: Pbkdf2Hooks,
): Promise<Uint8Array> => {
  const passwordBytes = utf8ToBytes(normalizePassword(password));

  return pbkdf2Sha256Async(passwordBytes, salt, iterations, KEY_BYTES, hooks);
};

/** kcv = HMAC-SHA256(key, "mfa-kcv|1") 的前 8 字节（规范 §4.1）。 */
export const computeKcv = (key: Uint8Array): Uint8Array => {
  return hmac(sha256, BLOCK_SIZE, key, utf8ToBytes(KCV_LABEL)).subarray(
    0,
    KCV_BYTES,
  );
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

/** 生成加密信封与文本（不落盘；调用方负责保存/复制）。 */
export const encryptEnvelope = async (
  items: BackupItem[],
  password: string,
  context: EncryptContext,
  hooks?: Pbkdf2Hooks,
): Promise<EncryptResult> => {
  if (items.length > MAX_ITEMS) {
    throw new BackupError({
      code: BackupErrorCode.E_PAYLOAD,
      detail: `条目数超过上限 ${MAX_ITEMS}`,
    });
  }

  const strength = checkPasswordStrength(password);

  if (!strength.ok) {
    throw new BackupError({
      code: BackupErrorCode.E_STRUCTURE,
      detail: strength.reason,
    });
  }

  const iterations = context.iterations ?? DEFAULT_ITERATIONS;
  const salt = await context.rng(SALT_BYTES);

  if (salt.length !== SALT_BYTES) {
    throw new BackupError({
      code: BackupErrorCode.E_STRUCTURE,
      detail: "随机源返回 salt 长度异常",
    });
  }

  const iv = await context.rng(IV_BYTES);

  if (iv.length !== IV_BYTES) {
    throw new BackupError({
      code: BackupErrorCode.E_STRUCTURE,
      detail: "随机源返回 iv 长度异常",
    });
  }

  const key = await deriveKey(password, salt, iterations, hooks);
  const kcv = computeKcv(key);
  const body = utf8ToBytes(stringifyPayload(items));
  const { ciphertext, tag } = aesGcmEncrypt(key, iv, utf8ToBytes(AAD), body);

  const createdAt = (context.now?.() ?? new Date()).toISOString();

  const envelope: Envelope = {
    format: "mfa",
    version: VERSION,
    method: "PBKDF2-SHA256/AES-256-GCM",
    key: {
      iterations,
      salt: encodeBase64(salt),
      iv: encodeBase64(iv),
      tag: encodeBase64(tag),
      kcv: encodeBase64(kcv),
    },
    data: encodeBase64(ciphertext),
    meta: {
      count: items.length,
      createdAt,
      source: context.source,
      app: context.app,
    },
  };

  return { text: stringifyEnvelope(envelope), envelope };
};

export interface DecryptResult {
  items: BackupItem[];
  invalid: InvalidItem[];
  envelope: Envelope;
}

/**
 * 解密信封（调用方应先用 parseEnvelope 完成结构校验，再要求用户输入口令）。
 * 失败抛 BackupError：kcv → E_PASSWORD；GCM → E_CORRUPT；payload/count → E_PAYLOAD。
 */
export const decryptEnvelope = async (
  envelope: Envelope,
  password: string,
  hooks?: Pbkdf2Hooks,
): Promise<DecryptResult> => {
  const salt = decodeBase64Strict(envelope.key.salt);
  const iv = decodeBase64Strict(envelope.key.iv);
  const tag = decodeBase64Strict(envelope.key.tag);
  const expectedKcv = decodeBase64Strict(envelope.key.kcv);

  const key = await deriveKey(password, salt, envelope.key.iterations, hooks);

  if (!constantTimeEqual(computeKcv(key), expectedKcv)) {
    throw new BackupError({ code: BackupErrorCode.E_PASSWORD });
  }

  const plaintext = aesGcmDecrypt(
    key,
    iv,
    utf8ToBytes(AAD),
    decodeBase64Strict(envelope.data),
    tag,
  );

  if (plaintext === null) {
    throw new BackupError({ code: BackupErrorCode.E_CORRUPT });
  }

  const payload = parsePayload(decodeUtf8(plaintext));

  if (!payload.ok) {
    throw new BackupError({
      code: BackupErrorCode.E_PAYLOAD,
      detail: payload.detail,
    });
  }

  if (payload.items.length + payload.invalid.length !== envelope.meta.count) {
    throw new BackupError({
      code: BackupErrorCode.E_PAYLOAD,
      detail: "meta.count 与解密条目数不一致",
    });
  }

  return { items: payload.items, invalid: payload.invalid, envelope };
};

const decodeUtf8 = (bytes: Uint8Array): string => {
  let out = "";
  let i = 0;

  while (i < bytes.length) {
    const b0 = bytes[i];

    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      i += 1;
    } else if ((b0 & 0xe0) === 0xc0) {
      out += String.fromCharCode(((b0 & 0x1f) << 6) | (bytes[i + 1] & 0x3f));
      i += 2;
    } else if ((b0 & 0xf0) === 0xe0) {
      out += String.fromCharCode(
        ((b0 & 0x0f) << 12) |
          ((bytes[i + 1] & 0x3f) << 6) |
          (bytes[i + 2] & 0x3f),
      );
      i += 3;
    } else {
      const code =
        ((b0 & 0x07) << 18) |
        ((bytes[i + 1] & 0x3f) << 12) |
        ((bytes[i + 2] & 0x3f) << 6) |
        (bytes[i + 3] & 0x3f);
      const offset = code - 0x10000;
      out += String.fromCharCode(
        0xd800 + (offset >>> 10),
        0xdc00 + (offset & 0x3ff),
      );
      i += 4;
    }
  }

  return out;
};
