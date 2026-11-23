// 后端加密备份接口（契约见 application-rs/docs/backup-format.md）。
// 口令只作为本次请求体发送，不进日志；错误码统一映射为可展示文案。
//
// 判定与错误构造交给 `api/request.ets`（响应体形状校验 / code===0 / HttpError），
// 本文件只额外做两件事：备份接口的独立超时、后端业务码 → 用户文案。
import { AxiosRequestConfig } from '@ohos/axios';
import { request } from './request';
import { AuthExpiredError, HttpError, toError } from '../utils/Errors';
import {
  BACKUP_EXPORT_PATH,
  BACKUP_IMPORT_PATH,
  BACKUP_KIND,
  BACKUP_TIMEOUT_MS,
  BackupEnvelope,
  BackupExportRequest,
  BackupImportRequest,
  BackupImportResponse
} from '../types/Backup';

const BACKEND_MESSAGES: Record<number, string> = {
  2023: '口令错误或备份已损坏',
  2024: '备份格式不正确或版本不受支持',
  2025: '口令长度不符合要求',
  2026: '没有可导出的账号',
  2027: '备份条目数超出上限（最多 50 条）',
  2028: '不支持的备份类型',
  9903: '导入未完全成功，请刷新后核对已写入的条目',
  9908: '加解密失败，请稍后重试',
};

// 业务码映射到固定文案；没有映射时保留 `request` 层给的后端 message / 兜底文案。
// 9903 仍需带 code 透出：页面靠它决定「部分写入后是否刷新列表」。
const mapped = (caught: Error): Error => {
  // 认证失效必须原样透出（页面靠 `instanceof AuthExpiredError` 跳过提示），不要替换成普通 HttpError
  if (caught instanceof AuthExpiredError) {
    return caught;
  }

  if (!(caught instanceof HttpError) || 'undefined' === typeof caught.code) {
    return caught;
  }

  const message: string | undefined = BACKEND_MESSAGES[caught.code];

  return 'undefined' === typeof message ? caught : new HttpError(message, caught.code);
};

// 服务端 PBKDF2 600k 次迭代，默认 5s 超时偏紧：备份接口单独 15s
const timeoutConfig = (): AxiosRequestConfig => ({ timeout: BACKUP_TIMEOUT_MS });

export class Backup {
  static async exportBackup(password: string): Promise<BackupEnvelope> {
    const body: BackupExportRequest = { kind: BACKUP_KIND, password };

    try {
      return await request<BackupEnvelope, BackupExportRequest>(BACKUP_EXPORT_PATH, body, timeoutConfig());
    } catch (e) {
      throw mapped(toError(e));
    }
  }

  static async importBackup(envelope: BackupEnvelope, password: string): Promise<number> {
    const body: BackupImportRequest = { kind: BACKUP_KIND, password, backup: envelope };

    try {
      const result: BackupImportResponse = await request<BackupImportResponse, BackupImportRequest>(BACKUP_IMPORT_PATH,
        body, timeoutConfig());

      return result.imported;
    } catch (e) {
      throw mapped(toError(e));
    }
  }
}
