// 加密备份前端编排：信封预检 → 口令策略 → 导出编排。
//
// 契约见 `application-rs/docs/backup-format.md`：加解密全部由服务端完成，本模块不持有明文条目；
// 口令只存在于页面内存与请求体，绝不写 preferences / 日志。
import {
  BACKUP_FORMAT,
  BACKUP_KIND,
  BACKUP_MAX_DATA_CHARS,
  BACKUP_MAX_ENVELOPE_TEXT_CHARS,
  BACKUP_MAX_ITEMS,
  BACKUP_VERSION,
  BackupCipher,
  BackupEnvelope,
  BackupKdf,
  BackupMeta
} from '../types/Backup';

// --- 预检错误 ---

/** 预检失败分类（仅用于日志/提示，服务端错误码在 `api/Backup.ets` 映射）。 */
export enum BackupParseCode {
  /** 文本不是合法 JSON */
  JSON = 'E_JSON',
  /** `format` 不是 `application` */
  FORMAT = 'E_FORMAT',
  /** `kind` 不是 `totp` */
  KIND = 'E_KIND',
  /** 信封版本高于当前支持 */
  VERSION = 'E_VERSION',
  /** 字段类型 / 必填项 / 时间格式异常 */
  STRUCTURE = 'E_STRUCTURE',
  /** 条目数或文本规模超出服务端上限 */
  LIMIT = 'E_LIMIT',
}

/** 预检错误：`code` 供日志/测试断言，`message` 可直接展示。 */
export class BackupParseError extends Error {
  readonly code: BackupParseCode;

  constructor(code: BackupParseCode, message: string) {
    super(message);
    this.name = 'BackupParseError';
    this.code = code;
  }
}

const fail = (code: BackupParseCode, message: string): BackupParseError => new BackupParseError(code, message);

// --- RFC3339 严格解析（后端 `meta.created_at`）---
// 不依赖 Date.parse：它对带偏移 ISO 串的容错行为不可靠，预检需要与后端一致地拒绝非法时间。

const TIMESTAMP_PATTERN: RegExp =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|([+-])(\d{2}):(\d{2}))$/;

const MIN_YEAR: number = 1970;

const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;

/** 严格解析为 epoch 毫秒；格式非法或日历非法（如 2026-02-30）返回 undefined。 */
export const parseCreatedAt = (text: string): number | undefined => {
  const match: RegExpExecArray | null = TIMESTAMP_PATTERN.exec(text);

  if (null === match) {
    return undefined;
  }

  const year: number = Number(match[1]);

  if (year < MIN_YEAR) {
    return undefined;
  }

  const month: number = Number(match[2]);
  const day: number = Number(match[3]);
  const hour: number = Number(match[4]);
  const minute: number = Number(match[5]);
  const second: number = Number(match[6]);

  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) {
    return undefined;
  }

  const millis: number = 'undefined' === typeof match[7] ? 0 : Number(match[7].slice(0, 3).padEnd(3, '0'));

  let offsetMinutes: number = 0;

  if ('Z' !== match[8]) {
    const offsetHours: number = Number(match[10]);
    const offsetMins: number = Number(match[11]);

    if (offsetHours > 14 || offsetMins > 59) {
      return undefined;
    }

    if (14 === offsetHours && 0 !== offsetMins) {
      return undefined;
    }

    offsetMinutes = (offsetHours * 60 + offsetMins) * ('-' === match[9] ? -1 : 1);
  }

  const wallClockMs: number = Date.UTC(year, month - 1, day, hour, minute, second, millis);
  const check: Date = new Date(wallClockMs);

  // 日历往返校验：拒绝正则挡不住的非法日期（Date.UTC 会把 2026-02-30 归一成 3-02）
  if (check.getUTCFullYear() !== year || check.getUTCMonth() !== month - 1 || check.getUTCDate() !== day ||
    check.getUTCHours() !== hour || check.getUTCMinutes() !== minute || check.getUTCSeconds() !== second ||
    check.getUTCMilliseconds() !== millis) {
    return undefined;
  }

  return wallClockMs - offsetMinutes * 60000;
};

/** `YYYY-MM-DD HH:mm`（设备本地时区）；解析失败回退原串，不显示 Invalid Date。 */
export const formatLocalDateTime = (iso: string): string => {
  const epochMs: number | undefined = parseCreatedAt(iso);

  if ('undefined' === typeof epochMs) {
    return iso;
  }

  const date: Date = new Date(epochMs);

  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

// --- 信封预检（只校验不消耗口令就能判定的事实：格式 / 类型 / 版本 / 条数上限 / 时间 / 文本规模）---

interface RawMeta {
  created_at?: string;
  count?: number;
}

interface RawKdf {
  alg?: string;
  iterations?: number;
  salt?: string;
}

interface RawCipher {
  alg?: string;
  nonce?: string;
}

interface RawEnvelope {
  format?: string;
  kind?: string;
  version?: number;
  meta?: RawMeta;
  kdf?: RawKdf;
  cipher?: RawCipher;
  data?: string;
}

const isRecord = (value: Object | undefined): boolean => 'object' === typeof value && null !== value;

const isNonEmptyString = (value: string | undefined): boolean => 'string' === typeof value && value.length > 0;

const isInt = (value: number | undefined): boolean => 'number' === typeof value && Number.isInteger(value);

/**
 * 校验任意来源（剪贴板 / 文件 / 导出响应）的信封对象；未知字段忽略。
 * 校验通过后重建对象，保证进入请求体的只包含契约字段。
 */
export const validateEnvelope = (value: Object): BackupEnvelope => {
  if (!isRecord(value)) {
    throw fail(BackupParseCode.STRUCTURE, '备份内容结构异常');
  }

  const raw: RawEnvelope = value as RawEnvelope;
  const format: string = 'undefined' === typeof raw.format ? '' : raw.format;
  const kind: string = 'undefined' === typeof raw.kind ? '' : raw.kind;
  const version: number = 'undefined' === typeof raw.version ? -1 : raw.version;

  if (format !== BACKUP_FORMAT) {
    throw fail(BackupParseCode.FORMAT, '不是本应用的备份文件');
  }

  if (kind !== BACKUP_KIND) {
    throw fail(BackupParseCode.KIND, '备份类型不受支持（仅支持 TOTP）');
  }

  if (!isInt(version)) {
    throw fail(BackupParseCode.STRUCTURE, '备份版本字段异常');
  }

  if (version > BACKUP_VERSION) {
    throw fail(BackupParseCode.VERSION, '备份版本不受支持，请升级应用');
  }

  if (version < BACKUP_VERSION) {
    throw fail(BackupParseCode.STRUCTURE, '备份版本字段异常');
  }

  if (!isRecord(raw.meta)) {
    throw fail(BackupParseCode.STRUCTURE, '备份元信息缺失');
  }

  const meta: RawMeta = raw.meta as RawMeta;
  const count: number = 'undefined' === typeof meta.count ? -1 : meta.count;
  const createdAt: string = 'undefined' === typeof meta.created_at ? '' : meta.created_at;

  if (!isInt(count) || count < 1) {
    throw fail(BackupParseCode.STRUCTURE, '备份条目数异常');
  }

  if (count > BACKUP_MAX_ITEMS) {
    throw fail(BackupParseCode.LIMIT, `备份条目数超出上限（最多 ${BACKUP_MAX_ITEMS} 条）`);
  }

  if (!isNonEmptyString(createdAt) || 'undefined' === typeof parseCreatedAt(createdAt)) {
    throw fail(BackupParseCode.STRUCTURE, '备份时间格式异常');
  }

  if (!isRecord(raw.kdf) || !isRecord(raw.cipher)) {
    throw fail(BackupParseCode.STRUCTURE, '备份加密参数缺失');
  }

  const kdf: RawKdf = raw.kdf as RawKdf;
  const cipher: RawCipher = raw.cipher as RawCipher;

  if (!isNonEmptyString(kdf.alg) || !isInt(kdf.iterations) || !isNonEmptyString(kdf.salt)) {
    throw fail(BackupParseCode.STRUCTURE, '备份加密参数异常');
  }

  if (!isNonEmptyString(cipher.alg) || !isNonEmptyString(cipher.nonce)) {
    throw fail(BackupParseCode.STRUCTURE, '备份加密参数异常');
  }

  const data: string = 'undefined' === typeof raw.data ? '' : raw.data;

  if (!isNonEmptyString(data)) {
    throw fail(BackupParseCode.STRUCTURE, '备份密文缺失');
  }

  if (data.length > BACKUP_MAX_DATA_CHARS) {
    throw fail(BackupParseCode.STRUCTURE, '备份数据过大');
  }

  const typedMeta: BackupMeta = { created_at: createdAt, count: count };
  const typedKdf: BackupKdf = { alg: kdf.alg as string, iterations: kdf.iterations as number, salt: kdf.salt as string };
  const typedCipher: BackupCipher = { alg: cipher.alg as string, nonce: cipher.nonce as string };

  return {
    format: BACKUP_FORMAT,
    kind: BACKUP_KIND,
    version: BACKUP_VERSION,
    meta: typedMeta,
    kdf: typedKdf,
    cipher: typedCipher,
    data: data,
  };
};

/** 文本 → 信封；先按请求体上限拦超大文本，非法 JSON 归为结构错误。 */
export const parseEnvelope = (text: string): BackupEnvelope => {
  if (text.length > BACKUP_MAX_ENVELOPE_TEXT_CHARS) {
    throw fail(BackupParseCode.LIMIT, '备份文本过大');
  }

  let value: Object;

  try {
    value = JSON.parse(text) as Object;
  } catch (e) {
    throw fail(BackupParseCode.JSON, '不是有效的备份文本');
  }

  return validateEnvelope(value);
};

// --- 口令策略（导出强度 / 导入可用性）---
// 与服务端语义一致：口令按 UTF-8 原字节参与 PBKDF2，**不 trim、不做 Unicode 归一化**；
// 导出时显式拒绝首尾空格，避免用户导出后无法再次输入相同口令。

const MIN_EXPORT_CODE_POINTS: number = 8;
const MAX_CODE_POINTS: number = 128;

/** 与服务端一致的弱口令黑名单（仅导出端提示，服务端不强制），按小写比较。 */
const WEAK_PASSWORDS: Set<string> = new Set<string>([
  '12345678',
  '123456789',
  '1234567890',
  'password',
  'password1',
  'qwertyui',
  'abc12345',
  '11111111',
  '88888888',
  'iloveyou',
]);

export interface PasswordCheck {
  ok: boolean;
  reason?: string;
}

/** 按 Unicode 标量计数：代理对算一个字符（与服务端口径一致）。 */
const codePointCount = (text: string): number => {
  let count: number = 0;

  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);

    if (code >= 0xD800 && code <= 0xDBFF) {
      i++;
    }

    count++;
  }

  return count;
};

const tooLong = (count: number): PasswordCheck | undefined =>
  count > MAX_CODE_POINTS ? { ok: false, reason: `口令最多 ${MAX_CODE_POINTS} 个字符` } : undefined;

/**
 * 导出端：两次输入一致 → 无首尾空格 → 8–128 个字符 → 非弱口令。
 * `confirm` 省略时跳过一致性校验。
 */
export const checkExportPassword = (password: string, confirm?: string): PasswordCheck => {
  if ('undefined' !== typeof confirm && password !== confirm) {
    return { ok: false, reason: '两次输入的口令不一致' };
  }

  if (password.trim() !== password) {
    return { ok: false, reason: '口令首尾不能包含空格' };
  }

  const count: number = codePointCount(password);

  if (count < MIN_EXPORT_CODE_POINTS) {
    return { ok: false, reason: `口令至少 ${MIN_EXPORT_CODE_POINTS} 个字符` };
  }

  const max: PasswordCheck | undefined = tooLong(count);

  if ('undefined' !== typeof max) {
    return max;
  }

  if (WEAK_PASSWORDS.has(password.toLowerCase())) {
    return { ok: false, reason: '口令过弱，请换一个' };
  }

  return { ok: true };
};

/** 导入端：只校验非空与上限（旧备份可能用短口令，保证兼容）。 */
export const checkImportPassword = (password: string): PasswordCheck => {
  const count: number = codePointCount(password);

  if (0 === count) {
    return { ok: false, reason: '请输入备份口令' };
  }

  const max: PasswordCheck | undefined = tooLong(count);

  return 'undefined' === typeof max ? { ok: true } : max;
};

// --- 导出编排 ---
// 条目读取、校验与加密全部在服务端完成；前端只在响应回来后再做一次预检，
// 避免后端升级 / 代理篡改后把异常信封落成文件。

export interface ExportResult {
  /** 可直接写文件 / 复制到剪贴板的 JSON 文本。 */
  text: string;
  count: number;
  /** 信封 `meta.created_at`（带时区偏移），页面按本地时间显示。 */
  createdAt: string;
}

export const buildExport = async (exportBackup: (password: string) => Promise<BackupEnvelope>,
  password: string): Promise<ExportResult> => {
  const envelope: BackupEnvelope = validateEnvelope(await exportBackup(password));

  return {
    text: JSON.stringify(envelope, null, 2),
    count: envelope.meta.count,
    createdAt: envelope.meta.created_at,
  };
};
