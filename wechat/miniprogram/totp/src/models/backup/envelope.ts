/**
 * 备份信封预检：只校验不消耗口令就能判定的事实（格式、类型、版本、条数上限、时间）。
 * 深层的 KDF / 密文 / 条目字段全部交给服务端，避免前端与后端校验规则漂移。
 */
import { FORMAT, KIND, MAX_ITEMS, VERSION } from "@constant/backup";
import { parseCreatedAt } from "@utils/datetime";
import type { BackupEnvelope } from "types/backup";
import { BackupParseError, BackupParseErrorCode } from "./errors";

/** 服务端 `data` 文本上限（512 KiB），超限请求会被拒绝，前端提前拦截。 */
const MAX_DATA_CHARS = 512 * 1024;

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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

  if (typeof value.version !== "number" || !Number.isInteger(value.version)) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份版本字段异常");
  }

  if (value.version !== VERSION) {
    return value.version > VERSION
      ? fail(BackupParseErrorCode.E_VERSION, "备份版本不受支持，请升级应用")
      : fail(BackupParseErrorCode.E_STRUCTURE, "备份版本字段异常");
  }

  if (!isRecord(value.meta)) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份元信息缺失");
  }

  const count = value.meta.count;

  if (typeof count !== "number" || !Number.isInteger(count) || count < 1) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份条目数异常");
  }

  if (count > MAX_ITEMS) {
    return fail(
      BackupParseErrorCode.E_LIMIT,
      `备份条目数超出上限（最多 ${MAX_ITEMS} 条）`,
    );
  }

  const createdAt = value.meta.created_at;

  if (
    typeof createdAt !== "string" ||
    parseCreatedAt(createdAt) === undefined
  ) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份时间格式异常");
  }

  if (!isRecord(value.kdf) || !isRecord(value.cipher)) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份加密参数缺失");
  }

  const data = value.data;

  if (typeof data !== "string" || data.length === 0) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份密文缺失");
  }

  if (data.length > MAX_DATA_CHARS) {
    return fail(BackupParseErrorCode.E_STRUCTURE, "备份数据过大");
  }

  return value as unknown as BackupEnvelope;
};

/** 文本 → 信封；非法 JSON 归为结构错误，便于页面统一提示。 */
export const parseEnvelope = (text: string): BackupEnvelope => {
  let value: unknown;

  try {
    value = JSON.parse(text);
  } catch (_e: unknown) {
    return fail(BackupParseErrorCode.E_JSON, "不是有效的备份文本");
  }

  return validateEnvelope(value);
};
