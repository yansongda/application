/**
 * 备份预检错误：仅用于“不花口令就能发现”的结构性问题（JSON、格式、版本、条数上限、时间）。
 * 口令错误 / 数据损坏 / 版本不支持等由服务端判定，错误信息在 `api/backup.ts` 映射。
 */

export enum BackupParseErrorCode {
  /** 文本不是合法 JSON。 */
  E_JSON = "E_JSON",
  /** `format` 不是 `application`。 */
  E_FORMAT = "E_FORMAT",
  /** `kind` 不是 `totp`。 */
  E_KIND = "E_KIND",
  /** 信封版本高于当前支持。 */
  E_VERSION = "E_VERSION",
  /** 字段类型 / 必填项 / 时间格式异常。 */
  E_STRUCTURE = "E_STRUCTURE",
  /** `meta.count` 超出服务端上限。 */
  E_LIMIT = "E_LIMIT",
}

export class BackupParseError extends Error {
  readonly code: BackupParseErrorCode;

  constructor(code: BackupParseErrorCode, message: string) {
    super(message);
    this.name = "BackupParseError";
    this.code = code;
  }
}
