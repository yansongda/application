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
  MAX_APP_LENGTH,
  MAX_CIPHERTEXT_BYTES,
  MAX_ITEMS,
  MAX_ITERATIONS,
  METHOD,
  MIN_ITERATIONS,
  SALT_BYTES,
  TAG_BYTES,
  VERSION,
} from "./spec";
import { parseCreatedAt } from "./time";

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

/**
 * meta 的规范序列化：字段顺序固定、紧凑 JSON（规范 §4.2 / §7）。
 * 它同时是 AAD 的尾部与信封内 `meta` 的字面来源，保证两处字节一致。
 * 要求 `count` 为整数、`createdAt` 为合法时间戳、`source` 为枚举、`app` 为可打印 ASCII，
 * 因此此处不会产生 `\"` / `\\` / `\uXXXX` 转义 —— 跨端零转义差异。
 */
export const canonicalMetaJson = (meta: EnvelopeMeta): string => {
  return JSON.stringify({
    count: meta.count,
    createdAt: meta.createdAt,
    source: meta.source,
    app: meta.app,
  });
};

/**
 * AAD = "mfa|" + version + "|" + method + "|" + canonicalMetaJson(meta)（规范 §4.2）。
 * 加密传常量 VERSION/METHOD；解密传信封里的 version/method，做到真正绑定头部字段。
 */
export const buildAad = (
  version: number,
  method: string,
  meta: EnvelopeMeta,
): string => {
  return `mfa|${version}|${method}|${canonicalMetaJson(meta)}`;
};

/** meta.app 只允许可打印 ASCII（0x20~0x7E）且不含引号/反斜杠（规范 §3.1）。 */
export const isValidApp = (value: unknown): value is string => {
  if (typeof value !== "string" || value.length > MAX_APP_LENGTH) {
    return false;
  }

  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);

    if (code < 0x20 || code > 0x7e || code === 0x22 || code === 0x5c) {
      return false;
    }
  }

  return true;
};

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

  // 严格解析（含日历合法性）：createdAt 参与 AAD，格式必须两端一致；
  // 允许 Z / ±HH:mm 与 0~3 位毫秒，导出端只写 ±HH:mm 且固定 3 位（规范 §4.1 / §7）。
  if (
    typeof createdAt !== "string" ||
    parseCreatedAt(createdAt) === undefined
  ) {
    return fail(
      BackupErrorCode.E_STRUCTURE,
      "meta.createdAt 非带时区的 ISO 串",
    );
  }

  const source = raw.meta.source;

  if (source !== "huawei" && source !== "wechat") {
    return fail(BackupErrorCode.E_STRUCTURE, "meta.source 非法");
  }

  const app = raw.meta.app;

  if (!isValidApp(app)) {
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

/** 紧凑 JSON，字段顺序固定（规范 §7）；meta 复用 canonicalMetaJson 与 AAD 字节一致。 */
export const stringifyEnvelope = (envelope: Envelope): string => {
  const key = envelope.key;

  return (
    `{"format":${JSON.stringify(envelope.format)},` +
    `"version":${envelope.version},` +
    `"method":${JSON.stringify(envelope.method)},` +
    `"key":{"iterations":${key.iterations},` +
    `"salt":${JSON.stringify(key.salt)},` +
    `"iv":${JSON.stringify(key.iv)},` +
    `"tag":${JSON.stringify(key.tag)},` +
    `"kcv":${JSON.stringify(key.kcv)}},` +
    `"data":${JSON.stringify(envelope.data)},` +
    `"meta":${canonicalMetaJson(envelope.meta)}}`
  );
};
