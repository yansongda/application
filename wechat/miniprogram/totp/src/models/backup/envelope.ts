/**
 * 备份信封预检：只校验不消耗口令就能判定的事实
 * （格式、类型、版本、条数上限、时间、文本规模）。
 * 深层的 KDF / 密文 / 条目字段全部交给服务端，避免前端与后端校验规则漂移。
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
import type { BackupEnvelope } from "types/backup";

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
