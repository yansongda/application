// 后端加密备份接口（契约见 application-rs/docs/backup-format.md）。
// 口令只作为本次请求体发送，不进日志；错误码统一映射为可展示文案。
import { AxiosRequestConfig, AxiosResponse } from '@ohos/axios';
import http, { Response } from '../utils/Http';
import { HttpError } from '../utils/Errors';
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

const describe = (code: number, message: string | undefined): string => {
  const mapped: string | undefined = BACKEND_MESSAGES[code];

  if ('undefined' !== typeof mapped) {
    return mapped;
  }

  if ('undefined' !== typeof message && message.length > 0) {
    return message;
  }

  return '操作失败，请重试';
};

// 服务端 PBKDF2 600k 次迭代，默认 5s 超时偏紧：备份接口单独 15s
const timeoutConfig = (): AxiosRequestConfig => ({ timeout: BACKUP_TIMEOUT_MS });

export class Backup {
  static async exportBackup(password: string): Promise<BackupEnvelope> {
    const response: AxiosResponse<Response<BackupEnvelope>> =
      await http.post<BackupEnvelope, AxiosResponse<Response<BackupEnvelope>>, BackupExportRequest>(
        BACKUP_EXPORT_PATH,
        {
          kind: BACKUP_KIND,
          password,
        },
        timeoutConfig());

    if (0 === response.data?.code && response.data?.data) {
      return response.data.data;
    }

    return Promise.reject(new HttpError(describe(response.data?.code ?? -1, response.data?.message),
      response.data?.code ?? -1));
  }

  static async importBackup(envelope: BackupEnvelope, password: string): Promise<number> {
    const response: AxiosResponse<Response<BackupImportResponse>> =
      await http.post<BackupImportResponse, AxiosResponse<Response<BackupImportResponse>>, BackupImportRequest>(
        BACKUP_IMPORT_PATH,
        {
          kind: BACKUP_KIND,
          password,
          backup: envelope,
        },
        timeoutConfig());

    if (0 === response.data?.code && response.data?.data) {
      return response.data.data.imported;
    }

    return Promise.reject(new HttpError(describe(response.data?.code ?? -1, response.data?.message),
      response.data?.code ?? -1));
  }
}
