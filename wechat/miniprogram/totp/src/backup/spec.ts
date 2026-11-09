/**
 * MFA 加密备份格式常量与错误码（唯一事实源：docs/specs/mfa-backup-v1.md）。
 * 本模块为纯常量，不依赖 wx / logger。
 */
export const FORMAT = "mfa";
// v1 尚未正式发布：AAD 纳入 meta（规范 §4.2 / §10.1 的预发布修订），不升 version。
export const VERSION = 1;
export const METHOD = "PBKDF2-SHA256/AES-256-GCM";
/** AAD 前缀；完整 AAD = AAD_PREFIX + canonicalMetaJson(meta)（见 envelope.ts buildAad）。 */
export const AAD_PREFIX = `mfa|${VERSION}|${METHOD}|`;
export const KCV_LABEL = "mfa-kcv|1";

export const SALT_BYTES = 16;
export const IV_BYTES = 12;
export const TAG_BYTES = 16;
export const KEY_BYTES = 32;
export const KCV_BYTES = 8;

export const MIN_ITERATIONS = 10000;
export const MAX_ITERATIONS = 500000;
export const DEFAULT_ITERATIONS = 100000;

export const MAX_ITEMS = 500;
export const MAX_CIPHERTEXT_BYTES = 1048576;

export const MIN_PASSWORD_CODE_POINTS = 8;
export const MAX_TAGS_PER_ITEM = 1;

/** meta.app 长度上限（字符集另见 envelope.ts：可打印 ASCII 且不含引号/反斜杠）。 */
export const MAX_APP_LENGTH = 32;

/** 明文 payload 的摘要算法（规范 §6）；库内自带，避免依赖业务层 types/totp。 */
export type BackupAlgorithm = "SHA1" | "SHA256" | "SHA512";

export enum BackupErrorCode {
  E_FORMAT = "E_FORMAT",
  E_VERSION = "E_VERSION",
  E_METHOD = "E_METHOD",
  E_STRUCTURE = "E_STRUCTURE",
  E_PASSWORD = "E_PASSWORD",
  E_CORRUPT = "E_CORRUPT",
  E_PAYLOAD = "E_PAYLOAD",
  // 运行时缺少 String.prototype.normalize 时的 fail-closed 错误（规范 §5）
  E_NORMALIZE = "E_NORMALIZE",
}

export interface BackupErrorOptions {
  code: BackupErrorCode;
  detail?: string;
}

export class BackupError extends Error {
  readonly code: BackupErrorCode;
  readonly detail: string | undefined;

  constructor(options: BackupErrorOptions) {
    super(backupErrorMessage(options.code));
    this.name = "BackupError";
    this.code = options.code;
    this.detail = options.detail;
  }
}

const MESSAGES: Record<BackupErrorCode, string> = {
  [BackupErrorCode.E_FORMAT]: "不是本应用备份文件",
  [BackupErrorCode.E_VERSION]: "备份版本过新，请升级应用",
  [BackupErrorCode.E_METHOD]: "不支持的加密方式",
  [BackupErrorCode.E_STRUCTURE]: "备份文件结构异常",
  [BackupErrorCode.E_PASSWORD]: "口令错误",
  [BackupErrorCode.E_CORRUPT]: "备份文件已损坏或被篡改",
  [BackupErrorCode.E_PAYLOAD]: "备份内容异常",
  [BackupErrorCode.E_NORMALIZE]: "当前系统不支持口令规范化",
};

export const backupErrorMessage = (code: BackupErrorCode): string => {
  return MESSAGES[code];
};

// 导出端强度校验：与华为端常量表逐条一致（文案不同也不影响互通，但保持两端口径相同）
export const WEAK_PASSWORDS: ReadonlyArray<string> = [
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
];
