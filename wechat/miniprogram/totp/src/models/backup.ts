/**
 * 加密备份模型：信封预检 → 口令策略 → 导出编排。
 *
 * 契约见 `application-rs/docs/backup-format.md`：加解密全部由服务端完成，
 * 本模块不持有明文条目；口令只存在于页面内存与请求体，绝不写 storage / 日志。
 * 预检错误对齐 `src/otp/errors.ts`（`as const` 字符串码 + `setPrototypeOf` 保 `instanceof`）。
 */
import {
  FORMAT,
  KIND,
  MAX_DATA_CHARS,
  MAX_ENVELOPE_TEXT_CHARS,
  MAX_ITEMS,
  VERSION,
} from "@constant/backup";
import { parseCreatedAt } from "@utils/datetime";
import type { BackupApi, BackupEnvelope } from "types/backup";

// --- 预检错误 ---

/**
 * 预检失败分类：仅用于前端提示、日志与测试断言；服务端错误码在 `api/backup.ts` 映射。
 * 与 `src/otp/errors.ts` 同构（字符串码冻结，v1 起仅允许新增）。
 */
export const BackupParseErrorCode = {
  E_JSON: "E_JSON", // 文本不是合法 JSON
  E_FORMAT: "E_FORMAT", // `format` 不是 `application`
  E_KIND: "E_KIND", // `kind` 不是 `totp`
  E_VERSION: "E_VERSION", // 信封版本高于当前支持
  E_STRUCTURE: "E_STRUCTURE", // 字段类型 / 必填项 / 时间格式异常
  E_LIMIT: "E_LIMIT", // 条目数或文本规模超出服务端上限
} as const;

export type BackupParseErrorCode =
  (typeof BackupParseErrorCode)[keyof typeof BackupParseErrorCode];

/**
 * 预检错误：`code` 供日志 / 测试断言，`message` 可直接展示。
 *
 * 微信编译会把 class 降级到 ES5（`project.config.json` 的 `es6 + enhance`），
 * 届时 `extends Error` 会丢原型链；这里显式 setPrototypeOf 保证 instanceof 可靠
 * （与 `src/otp/errors.ts` 的 OtpError 同一处理）。
 */
export class BackupParseError extends Error {
  readonly code: BackupParseErrorCode;

  constructor(code: BackupParseErrorCode, message: string) {
    super(message);
    this.name = "BackupParseError";
    Object.setPrototypeOf(this, BackupParseError.prototype);
    this.code = code;
  }
}

// --- 信封预检（只校验不消耗口令就能判定的事实：格式 / 类型 / 版本 / 条数上限 / 时间 / 文本规模）---

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === "object" && value !== null && !Array.isArray(value);
};

const isInt = (value: unknown): value is number => {
  return typeof value === "number" && Number.isInteger(value);
};

const isNonEmptyString = (value: unknown): value is string => {
  return typeof value === "string" && value.length > 0;
};

const fail = (code: BackupParseErrorCode, message: string): never => {
  throw new BackupParseError(code, message);
};

/** 校验任意来源（剪贴板 / 文件 / 导出响应）的信封对象；未知字段忽略。 */
export const validateEnvelope = (value: unknown): BackupEnvelope => {
  if (!isRecord(value)) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份内容结构异常");
  }

  if (value.format !== FORMAT) {
    return fail(BackupParseErrorCode.E_FORMAT, "不是本应用的备份文件");
  }

  if (value.kind !== KIND) {
    return fail(BackupParseErrorCode.E_KIND, "备份类型不受支持（仅支持 TOTP）");
  }

  if (!isInt(value.version)) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份版本字段异常");
  }

  if (value.version > VERSION) {
    return fail(BackupParseErrorCode.E_VERSION, "备份版本不受支持，请升级应用");
  }

  if (value.version < VERSION) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份版本字段异常");
  }

  const { meta, kdf, cipher, data } = value;

  if (!isRecord(meta)) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份元信息缺失");
  }

  if (!isInt(meta.count) || meta.count < 1) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份条目数异常");
  }

  if (meta.count > MAX_ITEMS) {
    return fail(
      BackupParseErrorCode.E_LIMIT,
      `备份条目数超出上限（最多 ${MAX_ITEMS} 条）`,
    );
  }

  const createdAt = meta.created_at;

  if (!isNonEmptyString(createdAt) || parseCreatedAt(createdAt) === undefined) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份时间格式异常");
  }

  if (!isRecord(kdf) || !isRecord(cipher)) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份加密参数缺失");
  }

  if (!isNonEmptyString(data)) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份密文缺失");
  }

  if (data.length > MAX_DATA_CHARS) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份数据过大");
  }

  return value as unknown as BackupEnvelope;
};

/** 文本 → 信封；先按请求体上限拦超大文本，非法 JSON 归为结构错误。 */
export const parseEnvelope = (text: string): BackupEnvelope => {
  if (text.length > MAX_ENVELOPE_TEXT_CHARS) {
    return fail(BackupParseErrorCode.E_LIMIT, "备份文本过大");
  }

  let value: unknown;

  try {
    value = JSON.parse(text);
  } catch (_e: unknown) {
    return fail(BackupParseErrorCode.E_JSON, "不是有效的备份文本");
  }

  return validateEnvelope(value);
};

// --- 口令策略（导出强度 / 导入可用性）---
// 与服务端语义一致：口令按 UTF-8 原字节参与 PBKDF2，**不 trim、不做 Unicode 归一化**；
// 导出时显式拒绝首尾空格，避免用户导出后无法再次输入相同口令。

const MIN_EXPORT_CODE_POINTS = 8;
const MAX_CODE_POINTS = 128;

/** 与服务端一致的弱口令黑名单（仅导出端提示，服务端不强制），按小写比较。 */
const WEAK_PASSWORDS: ReadonlySet<string> = new Set([
  "12345678",
  "123456789",
  "1234567890",
  "password",
  "password1",
  "qwertyui",
  "abc12345",
  "11111111",
  "88888888",
  "iloveyou",
]);

export type PasswordStrength = { ok: true } | { ok: false; reason: string };

const codePointCount = (text: string): number => {
  return Array.from(text).length;
};

/** 上限检查（导出/导入共用）；未超限返回 `undefined`。 */
const tooLong = (count: number): PasswordStrength | undefined => {
  return count > MAX_CODE_POINTS
    ? { ok: false, reason: `口令最多 ${MAX_CODE_POINTS} 个字符` }
    : undefined;
};

/**
 * 导出端：两次输入一致 → 无首尾空格 → 8–128 个 Unicode 字符 → 非弱口令。
 * `confirm` 省略时跳过一致性校验（供单独校验强度的场景使用）。
 */
export const checkExportPassword = (
  password: string,
  confirm?: string,
): PasswordStrength => {
  if (confirm !== undefined && password !== confirm) {
    return { ok: false, reason: "两次输入的口令不一致" };
  }

  if (password.trim() !== password) {
    return { ok: false, reason: "口令首尾不能包含空格" };
  }

  const count = codePointCount(password);

  if (count < MIN_EXPORT_CODE_POINTS) {
    return { ok: false, reason: `口令至少 ${MIN_EXPORT_CODE_POINTS} 个字符` };
  }

  const max = tooLong(count);

  if (max !== undefined) {
    return max;
  }

  if (WEAK_PASSWORDS.has(password.toLowerCase())) {
    return { ok: false, reason: "口令过弱，请换一个" };
  }

  return { ok: true };
};

/** 导入端：只校验非空与上限（旧备份可能用短口令，保证兼容）。 */
export const checkImportPassword = (password: string): PasswordStrength => {
  const count = codePointCount(password);

  if (count === 0) {
    return { ok: false, reason: "请输入备份口令" };
  }

  return tooLong(count) ?? { ok: true };
};

// --- 导出编排 ---
// 条目读取、校验与加密全部在服务端完成；前端不再持有明文打包结果。
// 导入无编排层：服务端一次请求完成解密与批量写入，页面直接调用 `backupApi.importBackup`。

export interface ExportResult {
  /** 可直接写文件 / 复制到剪贴板的 JSON 文本。 */
  text: string;
  count: number;
  /** 信封 meta.created_at（带时区偏移），页面按本地时间显示。 */
  createdAt: string;
}

export const buildExport = async (
  api: Pick<BackupApi, "exportBackup">,
  password: string,
): Promise<ExportResult> => {
  // 服务端响应也走一次预检：避免后端升级 / 代理篡改后把异常信封落成文件
  const envelope = validateEnvelope(await api.exportBackup(password));

  return {
    text: JSON.stringify(envelope, null, 2),
    count: envelope.meta.count,
    createdAt: envelope.meta.created_at,
  };
};
