/**
 * MFA 备份信封：结构定义、严格解析（规范 §3.1 / §7 / §8）与序列化。
 * 纯函数，不依赖 wx / logger。
 */
import { decodeBase64Strict } from "./base64";
import {
  BackupErrorCode,
  FORMAT,
  IV_BYTES,
  KCV_BYTES,
  MAX_CIPHERTEXT_BYTES,
  MAX_ITEMS,
  MAX_ITERATIONS,
  METHOD,
  MIN_ITERATIONS,
  SALT_BYTES,
  TAG_BYTES,
  VERSION,
} from "./spec";

export type EnvelopeSource = "huawei" | "wechat";

export interface EnvelopeKey {
  iterations: number;
  salt: string;
  iv: string;
  tag: string;
  kcv: string;
}

export interface EnvelopeMeta {
  count: number;
  createdAt: string;
  source: EnvelopeSource;
  app: string;
}

export interface Envelope {
  format: string;
  version: number;
  method: string;
  key: EnvelopeKey;
  data: string;
  meta: EnvelopeMeta;
}

export interface ParseError {
  ok: false;
  code: BackupErrorCode;
  detail: string;
}

export type ParseEnvelopeResult = { ok: true; envelope: Envelope } | ParseError;

const CREATED_AT_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/;

const fail = (code: BackupErrorCode, detail: string): ParseEnvelopeResult => {
  return { ok: false, code, detail };
};

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === "object" && value !== null && !Array.isArray(value);
};

// 只用于结构校验；解码结果丢弃（crypto 需要时重新解码，避免把字节挂在公开类型上）
const assertBase64Length = (
  value: unknown,
  expected: number,
  field: string,
): ParseEnvelopeResult | undefined => {
  if (typeof value !== "string") {
    return fail(BackupErrorCode.E_STRUCTURE, `${field} 不是字符串`);
  }

  let bytes: Uint8Array;

  try {
    bytes = decodeBase64Strict(value);
  } catch {
    return fail(BackupErrorCode.E_STRUCTURE, `${field} 不是规范 base64`);
  }

  if (bytes.length !== expected) {
    return fail(
      BackupErrorCode.E_STRUCTURE,
      `${field} 长度应为 ${expected} 字节`,
    );
  }

  return undefined;
};

/**
 * 严格按规范 §8 顺序解析：
 * JSON/format → version（>1）→ method → 结构与长度 → meta。
 * kcv / GCM / payload 判定由 crypto.ts 与 payload.ts 承担。
 */
export const parseEnvelope = (text: string): ParseEnvelopeResult => {
  let raw: unknown;

  try {
    raw = JSON.parse(text.trim());
  } catch {
    return fail(BackupErrorCode.E_FORMAT, "不是合法 JSON");
  }

  if (!isRecord(raw) || raw.format !== FORMAT) {
    return fail(BackupErrorCode.E_FORMAT, "format 不为 mfa");
  }

  const version = raw.version;

  if (typeof version === "number" && Number.isInteger(version) && version > 1) {
    return fail(BackupErrorCode.E_VERSION, `不支持的版本 ${version}`);
  }

  if (raw.method !== METHOD) {
    return fail(BackupErrorCode.E_METHOD, "method 不在注册表");
  }

  // 步骤 4：结构 / 长度 / 范围（非整数或 < 1 的 version 落到这里）
  if (!Number.isInteger(version) || version !== VERSION) {
    return fail(BackupErrorCode.E_STRUCTURE, "version 必须恰为 1");
  }

  if (!isRecord(raw.key)) {
    return fail(BackupErrorCode.E_STRUCTURE, "key 不是对象");
  }

  const iterations = raw.key.iterations;

  if (
    !Number.isInteger(iterations) ||
    (iterations as number) < MIN_ITERATIONS ||
    (iterations as number) > MAX_ITERATIONS
  ) {
    return fail(BackupErrorCode.E_STRUCTURE, "iterations 超出区间");
  }

  const keyChecks: Array<[unknown, number, string]> = [
    [raw.key.salt, SALT_BYTES, "key.salt"],
    [raw.key.iv, IV_BYTES, "key.iv"],
    [raw.key.tag, TAG_BYTES, "key.tag"],
    [raw.key.kcv, KCV_BYTES, "key.kcv"],
  ];

  for (const [value, expected, field] of keyChecks) {
    const problem = assertBase64Length(value, expected, field);

    if (problem !== undefined) {
      return problem;
    }
  }

  if (typeof raw.data !== "string") {
    return fail(BackupErrorCode.E_STRUCTURE, "data 不是字符串");
  }

  let dataBytes: Uint8Array;

  try {
    dataBytes = decodeBase64Strict(raw.data);
  } catch {
    return fail(BackupErrorCode.E_STRUCTURE, "data 不是规范 base64");
  }

  if (dataBytes.length < 1 || dataBytes.length > MAX_CIPHERTEXT_BYTES) {
    return fail(BackupErrorCode.E_STRUCTURE, "data 长度超出区间");
  }

  if (!isRecord(raw.meta)) {
    return fail(BackupErrorCode.E_STRUCTURE, "meta 不是对象");
  }

  const count = raw.meta.count;

  if (
    !Number.isInteger(count) ||
    (count as number) < 0 ||
    (count as number) > MAX_ITEMS
  ) {
    return fail(BackupErrorCode.E_STRUCTURE, "meta.count 超出区间");
  }

  const createdAt = raw.meta.createdAt;

  // 与华为端逐字一致：只校验规范 §7 的 UTC 格式（Date.parse 会引入两端不同的额外拒绝面）
  if (typeof createdAt !== "string" || !CREATED_AT_PATTERN.test(createdAt)) {
    return fail(BackupErrorCode.E_STRUCTURE, "meta.createdAt 非 UTC ISO 串");
  }

  const source = raw.meta.source;

  if (source !== "huawei" && source !== "wechat") {
    return fail(BackupErrorCode.E_STRUCTURE, "meta.source 非法");
  }

  const app = raw.meta.app;

  if (typeof app !== "string" || app.length > 32) {
    return fail(BackupErrorCode.E_STRUCTURE, "meta.app 非法");
  }

  // 未知字段按规范忽略（前向兼容）
  return {
    ok: true,
    envelope: {
      format: FORMAT,
      version: VERSION,
      method: METHOD,
      key: {
        iterations: iterations as number,
        salt: raw.key.salt as string,
        iv: raw.key.iv as string,
        tag: raw.key.tag as string,
        kcv: raw.key.kcv as string,
      },
      data: raw.data,
      meta: {
        count: count as number,
        createdAt,
        source,
        app,
      },
    },
  };
};

/** 紧凑 JSON，字段顺序固定（规范 §7）。 */
export const stringifyEnvelope = (envelope: Envelope): string => {
  return JSON.stringify({
    format: envelope.format,
    version: envelope.version,
    method: envelope.method,
    key: {
      iterations: envelope.key.iterations,
      salt: envelope.key.salt,
      iv: envelope.key.iv,
      tag: envelope.key.tag,
      kcv: envelope.key.kcv,
    },
    data: envelope.data,
    meta: {
      count: envelope.meta.count,
      createdAt: envelope.meta.createdAt,
      source: envelope.meta.source,
      app: envelope.meta.app,
    },
  });
};
