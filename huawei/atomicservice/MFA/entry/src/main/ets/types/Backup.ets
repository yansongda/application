// 后端加密备份契约（application-rs/docs/backup-format.md，v1）。
// 与微信端 `wechat/miniprogram/totp/src/constant/backup.ts` / `types/backup.d.ts` 逐字段一致；
// 加解密全部在服务端完成，前端只做结构预检与口令策略，**不得**引入端内 PBKDF2 / AES-GCM。

/** 信封 `format`（后端 `service::backup::FORMAT`）。 */
export const BACKUP_FORMAT: string = 'application';
/** 备份类型：华为端只消费 TOTP。 */
export const BACKUP_KIND: string = 'totp';
/** 信封版本（v1）。 */
export const BACKUP_VERSION: number = 1;
/** 服务端单类备份条目上限（导出/导入共用）。 */
export const BACKUP_MAX_ITEMS: number = 50;
/** 信封 `data` 字段字符上限（后端 512 KiB）。 */
export const BACKUP_MAX_DATA_CHARS: number = 512 * 1024;
/** 备份文本整体字符上限：后端限制的是整个请求体，导入时必须单独卡住文本总长。 */
export const BACKUP_MAX_ENVELOPE_TEXT_CHARS: number = 512 * 1024;
/** 复制到剪贴板的安全上限（远小于请求体上限，避免系统剪贴板截断）。 */
export const BACKUP_CLIPBOARD_MAX_CHARS: number = 65536;
/** 备份接口超时：服务端 PBKDF2 600k 次迭代，默认 5s 偏紧，固定 15s。 */
export const BACKUP_TIMEOUT_MS: number = 15000;

export const BACKUP_EXPORT_PATH: string = 'api/v1/backup/export';
export const BACKUP_IMPORT_PATH: string = 'api/v1/backup/import';

/** 信封元信息：`created_at` 为带时区偏移的 RFC3339 时间。 */
export interface BackupMeta {
  created_at: string;
  /** 明文条目数；解密后必须与 payload 数组长度一致（服务端校验）。 */
  count: number;
}

export interface BackupKdf {
  alg: string;
  iterations: number;
  /** base64（标准字母表）编码的 16 字节 salt。 */
  salt: string;
}

export interface BackupCipher {
  alg: string;
  /** base64（标准字母表）编码的 12 字节 nonce。 */
  nonce: string;
}

/** `POST /api/v1/backup/export` 的响应 `data`，也是 `/import` 请求体的 `backup` 字段。 */
export interface BackupEnvelope {
  format: string;
  kind: string;
  version: number;
  meta: BackupMeta;
  kdf: BackupKdf;
  cipher: BackupCipher;
  /** base64 编码的 `密文 || 16 字节 GCM tag`。 */
  data: string;
}

export interface BackupExportRequest {
  kind: string;
  password: string;
}

export interface BackupImportRequest {
  kind: string;
  password: string;
  backup: BackupEnvelope;
}

export interface BackupImportResponse {
  imported: number;
}

/** 备份页模式：从「用户详情 → 更多」的两个入口分别进入，页面只展示对应卡片。 */
export enum BackupPageMode {
  EXPORT = 'export',
  IMPORT = 'import',
  BOTH = 'both',
}

export class BackupPageParams {
  mode: BackupPageMode;

  constructor(mode: BackupPageMode) {
    this.mode = mode;
  }
}
