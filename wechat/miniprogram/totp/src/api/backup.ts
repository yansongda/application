/**
 * 后端加密备份接口（契约见 application-rs/docs/backup-format.md）。
 * 口令只作为本次请求体发送，不进日志；错误码统一映射为可展示文案。
 */
import { KIND, PATH } from "@constant/backup";
import { CODE } from "@constant/error";
import { HttpError } from "@models/error";
import error from "@utils/error";
import http from "@utils/http";
import logger from "@utils/logger";
import type { BackupEnvelope, ImportResponse } from "types/backup";

// 服务端 PBKDF2 600k 次迭代，微信默认 5s 超时偏紧
const TIMEOUT_MS = 15000;

const BACKEND_MESSAGES: Record<number, string> = {
  2023: "口令错误或备份已损坏",
  2024: "备份格式不正确或版本不受支持",
  2025: "口令长度不符合要求",
  2026: "没有可导出的账号",
  2027: "备份条目数超出上限（最多 50 条）",
  2028: "不支持的备份类型",
  9903: "导入未完全成功，请刷新后核对已写入的条目",
  9908: "加解密失败，请稍后重试",
};

const describe = (e: unknown): string => {
  if (e instanceof HttpError) {
    const mapped = BACKEND_MESSAGES[e.code];

    if (mapped !== undefined) {
      return mapped;
    }
  }

  return error.getErrorMessage(e);
};

const exportBackup = async (password: string): Promise<BackupEnvelope> => {
  try {
    return await http.post<BackupEnvelope>(
      PATH.EXPORT,
      { kind: KIND, password },
      TIMEOUT_MS,
    );
  } catch (e: unknown) {
    logger.error("导出加密备份失败", e);

    throw new HttpError(CODE.HTTP_API_BACKUP_EXPORT, describe(e));
  }
};

const importBackup = async (
  backup: BackupEnvelope,
  password: string,
): Promise<number> => {
  try {
    const result = await http.post<ImportResponse>(
      PATH.IMPORT,
      { kind: KIND, password, backup },
      TIMEOUT_MS,
    );

    return result.imported;
  } catch (e: unknown) {
    logger.error("导入加密备份失败", e);

    throw new HttpError(CODE.HTTP_API_BACKUP_IMPORT, describe(e));
  }
};

export default { exportBackup, importBackup };
