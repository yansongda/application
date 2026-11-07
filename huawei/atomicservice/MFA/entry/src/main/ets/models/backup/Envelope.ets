// 备份信封：结构定义、严格解析（规范 §3.1 / §7 / §8）与序列化。
// 纯函数（不依赖系统 API，Local Test 可跑）：base64 解码器同样为纯 JS 实现，
// 这样「拒绝空白/非标准字母表/缺失 padding」的判定两端逐字一致。
import {
  BackupError,
  BackupErrorCode,
  BackupSpec
} from './Spec';

const BASE64_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function buildBase64Table(): number[] {
  const table: number[] = [];

  for (let i = 0; i < 128; i++) {
    table.push(-1);
  }

  for (let i = 0; i < BASE64_ALPHABET.length; i++) {
    table[BASE64_ALPHABET.charCodeAt(i)] = i;
  }

  return table;
}

const BASE64_TABLE: number[] = buildBase64Table();

export function encodeBase64(bytes: Uint8Array): string {
  const parts: string[] = [];

  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;

    parts.push(BASE64_ALPHABET.charAt(b0 >> 2));
    parts.push(BASE64_ALPHABET.charAt(((b0 & 0x03) << 4) | (b1 >> 4)));

    if (i + 1 < bytes.length) {
      parts.push(BASE64_ALPHABET.charAt(((b1 & 0x0f) << 2) | (b2 >> 6)));
    } else {
      parts.push('=');
    }

    if (i + 2 < bytes.length) {
      parts.push(BASE64_ALPHABET.charAt(b2 & 0x3f));
    } else {
      parts.push('=');
    }
  }

  return parts.join('');
}

// 严格解码：拒绝空白、非标准字母表、padding 缺失/多余、长度非 4 的倍数（规范 §7）。
export function decodeBase64Strict(text: string): Uint8Array {
  if (text.length === 0 || text.length % 4 !== 0) {
    throw new BackupError(BackupErrorCode.E_STRUCTURE, 'base64 长度非法');
  }

  let padding: number = 0;

  if (text.endsWith('==')) {
    padding = 2;
  } else if (text.endsWith('=')) {
    padding = 1;
  }

  const dataLength: number = text.length - padding;

  if (dataLength % 4 === 1) {
    throw new BackupError(BackupErrorCode.E_STRUCTURE, 'base64 尾块非法');
  }

  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);

    if (ch === '=') {
      if (i < dataLength) {
        throw new BackupError(BackupErrorCode.E_STRUCTURE, 'base64 padding 位置非法');
      }

      continue;
    }

    const code: number = text.charCodeAt(i);

    if (code >= 128 || BASE64_TABLE[code] < 0) {
      throw new BackupError(BackupErrorCode.E_STRUCTURE, 'base64 字符非法');
    }
  }

  const outputLength: number = (text.length / 4) * 3 - padding;
  const out: Uint8Array = new Uint8Array(outputLength);
  let outIndex: number = 0;

  for (let i = 0; i < text.length; i += 4) {
    const c0: number = BASE64_TABLE[text.charCodeAt(i)];
    const c1: number = BASE64_TABLE[text.charCodeAt(i + 1)];
    const c2: number = i + 2 < dataLength ? BASE64_TABLE[text.charCodeAt(i + 2)] : 0;
    const c3: number = i + 3 < dataLength ? BASE64_TABLE[text.charCodeAt(i + 3)] : 0;

    out[outIndex++] = ((c0 << 2) | (c1 >> 4)) & 0xff;

    if (outIndex < outputLength) {
      out[outIndex++] = (((c1 & 0x0f) << 4) | (c2 >> 2)) & 0xff;
    }

    if (outIndex < outputLength) {
      out[outIndex++] = (((c2 & 0x03) << 6) | c3) & 0xff;
    }
  }

  return out;
}

export interface IEnvelopeKey {
  iterations: number;
  salt: string;
  iv: string;
  tag: string;
  kcv: string;
}

export interface IEnvelopeMeta {
  count: number;
  createdAt: string;
  source: string;
  app: string;
}

export interface IEnvelope {
  format: string;
  version: number;
  method: string;
  key: IEnvelopeKey;
  data: string;
  meta: IEnvelopeMeta;
}

interface IRawKey {
  iterations?: number;
  salt?: string;
  iv?: string;
  tag?: string;
  kcv?: string;
}

interface IRawMeta {
  count?: number;
  createdAt?: string;
  source?: string;
  app?: string;
}

interface IRawEnvelope {
  format?: string;
  version?: number;
  method?: string;
  key?: IRawKey;
  data?: string;
  meta?: IRawMeta;
}

export class EnvelopeParseResult {
  readonly ok: boolean;
  readonly envelope: IEnvelope | undefined;
  readonly code: BackupErrorCode;
  readonly detail: string;

  constructor(ok: boolean, envelope: IEnvelope | undefined, code: BackupErrorCode,
    detail: string) {
    this.ok = ok;
    this.envelope = envelope;
    this.code = code;
    this.detail = detail;
  }
}

function fail(code: BackupErrorCode, detail: string): EnvelopeParseResult {
  return new EnvelopeParseResult(false, undefined, code, detail);
}

function pass(envelope: IEnvelope): EnvelopeParseResult {
  return new EnvelopeParseResult(true, envelope, BackupErrorCode.E_STRUCTURE, '');
}

// ISO 8601 UTC：YYYY-MM-DDTHH:mm:ss[.f{1,3}]Z（规范 §7，只接受 Z 结尾）
function isIsoUtcTime(text: string): boolean {
  if (text.length !== 20 && text.length !== 22 && text.length !== 23 && text.length !== 24) {
    return false;
  }

  if (text.charAt(4) !== '-' || text.charAt(7) !== '-' || text.charAt(10) !== 'T' ||
    text.charAt(13) !== ':' || text.charAt(16) !== ':') {
    return false;
  }

  const digits: number[] = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18];

  for (const index of digits) {
    const code: number = text.charCodeAt(index);

    if (code < 48 || code > 57) {
      return false;
    }
  }

  if (text.length === 20) {
    return text.charAt(19) === 'Z';
  }

  if (text.charAt(19) !== '.') {
    return false;
  }

  const fracLength: number = text.length - 21;

  if (fracLength < 1 || fracLength > 3) {
    return false;
  }

  for (let i = 20; i < 20 + fracLength; i++) {
    const code: number = text.charCodeAt(i);

    if (code < 48 || code > 57) {
      return false;
    }
  }

  return text.charAt(text.length - 1) === 'Z';
}

function checkBase64Length(value: string | undefined, expected: number, field: string): EnvelopeParseResult | undefined {
  if ('undefined' === typeof value) {
    return fail(BackupErrorCode.E_STRUCTURE, `${field} 缺失`);
  }

  let bytes: Uint8Array;

  try {
    bytes = decodeBase64Strict(value);
  } catch (e) {
    return fail(BackupErrorCode.E_STRUCTURE, `${field} 不是规范 base64`);
  }

  if (bytes.length !== expected) {
    return fail(BackupErrorCode.E_STRUCTURE, `${field} 长度应为 ${expected} 字节`);
  }

  return undefined;
}

// 严格按规范 §8 顺序：JSON/format → version(>1) → method → 结构/长度 → meta
export function parseEnvelope(text: string): EnvelopeParseResult {
  let parsed: Object | null = null;

  try {
    parsed = JSON.parse(text.trim()) as Object;
  } catch (e) {
    return fail(BackupErrorCode.E_FORMAT, '不是合法 JSON');
  }

  if (null === parsed) {
    return fail(BackupErrorCode.E_FORMAT, '不是 JSON 对象');
  }

  const raw: IRawEnvelope = parsed as IRawEnvelope;

  if (BackupSpec.FORMAT !== raw.format) {
    return fail(BackupErrorCode.E_FORMAT, 'format 不为 mfa');
  }

  const version: number | undefined = raw.version;

  if ('number' === typeof version && Number.isInteger(version) && version > BackupSpec.VERSION) {
    return fail(BackupErrorCode.E_VERSION, `不支持的版本 ${version}`);
  }

  if (BackupSpec.METHOD !== raw.method) {
    return fail(BackupErrorCode.E_METHOD, 'method 不在注册表');
  }

  if ('number' !== typeof version || !Number.isInteger(version) || version !== BackupSpec.VERSION) {
    return fail(BackupErrorCode.E_STRUCTURE, 'version 必须恰为 1');
  }

  const key: IRawKey | undefined = raw.key;

  if ('undefined' === typeof key) {
    return fail(BackupErrorCode.E_STRUCTURE, 'key 缺失');
  }

  const iterations: number | undefined = key.iterations;

  if ('number' !== typeof iterations || !Number.isInteger(iterations) ||
    iterations < BackupSpec.MIN_ITERATIONS || iterations > BackupSpec.MAX_ITERATIONS) {
    return fail(BackupErrorCode.E_STRUCTURE, 'iterations 超出区间');
  }

  const saltCheck: EnvelopeParseResult | undefined =
    checkBase64Length(key.salt, BackupSpec.SALT_BYTES, 'key.salt');

  if ('undefined' !== typeof saltCheck) {
    return saltCheck;
  }

  const ivCheck: EnvelopeParseResult | undefined =
    checkBase64Length(key.iv, BackupSpec.IV_BYTES, 'key.iv');

  if ('undefined' !== typeof ivCheck) {
    return ivCheck;
  }

  const tagCheck: EnvelopeParseResult | undefined =
    checkBase64Length(key.tag, BackupSpec.TAG_BYTES, 'key.tag');

  if ('undefined' !== typeof tagCheck) {
    return tagCheck;
  }

  const kcvCheck: EnvelopeParseResult | undefined =
    checkBase64Length(key.kcv, BackupSpec.KCV_BYTES, 'key.kcv');

  if ('undefined' !== typeof kcvCheck) {
    return kcvCheck;
  }

  if ('string' !== typeof raw.data) {
    return fail(BackupErrorCode.E_STRUCTURE, 'data 不是字符串');
  }

  let dataBytes: Uint8Array;

  try {
    dataBytes = decodeBase64Strict(raw.data);
  } catch (e) {
    return fail(BackupErrorCode.E_STRUCTURE, 'data 不是规范 base64');
  }

  if (dataBytes.length < 1 || dataBytes.length > BackupSpec.MAX_CIPHERTEXT_BYTES) {
    return fail(BackupErrorCode.E_STRUCTURE, 'data 长度超出区间');
  }

  const meta: IRawMeta | undefined = raw.meta;

  if ('undefined' === typeof meta) {
    return fail(BackupErrorCode.E_STRUCTURE, 'meta 缺失');
  }

  const count: number | undefined = meta.count;

  if ('number' !== typeof count || !Number.isInteger(count) ||
    count < 0 || count > BackupSpec.MAX_ITEMS) {
    return fail(BackupErrorCode.E_STRUCTURE, 'meta.count 超出区间');
  }

  const createdAt: string | undefined = meta.createdAt;

  if ('string' !== typeof createdAt || !isIsoUtcTime(createdAt)) {
    return fail(BackupErrorCode.E_STRUCTURE, 'meta.createdAt 非 UTC ISO 串');
  }

  const source: string | undefined = meta.source;

  if ('huawei' !== source && 'wechat' !== source) {
    return fail(BackupErrorCode.E_STRUCTURE, 'meta.source 非法');
  }

  const app: string | undefined = meta.app;

  if ('string' !== typeof app || app.length > 32) {
    return fail(BackupErrorCode.E_STRUCTURE, 'meta.app 非法');
  }

  // 未知字段按规范忽略（前向兼容）
  const envelope: IEnvelope = {
    format: BackupSpec.FORMAT,
    version: BackupSpec.VERSION,
    method: BackupSpec.METHOD,
    key: {
      iterations: iterations,
      salt: key.salt as string,
      iv: key.iv as string,
      tag: key.tag as string,
      kcv: key.kcv as string
    },
    data: raw.data,
    meta: {
      count: count,
      createdAt: createdAt,
      source: source,
      app: app
    }
  };

  return pass(envelope);
}

// 紧凑 JSON，字段顺序固定（规范 §7）
export function stringifyEnvelope(envelope: IEnvelope): string {
  const plain: IEnvelope = {
    format: envelope.format,
    version: envelope.version,
    method: envelope.method,
    key: {
      iterations: envelope.key.iterations,
      salt: envelope.key.salt,
      iv: envelope.key.iv,
      tag: envelope.key.tag,
      kcv: envelope.key.kcv
    },
    data: envelope.data,
    meta: {
      count: envelope.meta.count,
      createdAt: envelope.meta.createdAt,
      source: envelope.meta.source,
      app: envelope.meta.app
    }
  };

  return JSON.stringify(plain);
}
