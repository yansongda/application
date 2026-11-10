/**
 * 后端加密备份信封（POST /api/v1/backup/export 响应、/import 请求的 backup 字段）。
 * 字段名与 application-rs `service::backup::Envelope` 保持一致（snake_case）。
 */
export interface BackupMeta {
  /** 带时区偏移的 RFC3339 时间，例如 `2026-06-28T14:30:00+08:00`。 */
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

export interface ImportResponse {
  imported: number;
}
