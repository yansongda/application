// MFA 加密备份格式常量与错误码（唯一事实源：docs/specs/mfa-backup-v1.md）。
// 纯常量模块：不依赖系统 API，Local Test 可直接加载。
export class BackupSpec {
  static readonly FORMAT: string = 'mfa';
  static readonly VERSION: number = 1;
  static readonly METHOD: string = 'PBKDF2-SHA256/AES-256-GCM';
  static readonly AAD: string = 'mfa|1|PBKDF2-SHA256/AES-256-GCM';
  static readonly KCV_LABEL: string = 'mfa-kcv|1';

  static readonly SALT_BYTES: number = 16;
  static readonly IV_BYTES: number = 12;
  static readonly TAG_BYTES: number = 16;
  static readonly KEY_BYTES: number = 32;
  static readonly KCV_BYTES: number = 8;

  static readonly MIN_ITERATIONS: number = 10000;
  static readonly MAX_ITERATIONS: number = 500000;
  static readonly DEFAULT_ITERATIONS: number = 100000;

  static readonly MAX_ITEMS: number = 500;
  static readonly MAX_CIPHERTEXT_BYTES: number = 1048576;
  static readonly MIN_PASSWORD_CODE_POINTS: number = 8;
  static readonly MAX_TAGS_PER_ITEM: number = 1;

  // 与微信端常量表逐条一致（文案不影响互通，但两端强度口径必须相同）
  static readonly WEAK_PASSWORDS: string[] = [
    '12345678',
    '123456789',
    '1234567890',
    'password',
    'password1',
    'qwertyui',
    'abc12345',
    '11111111',
    '88888888',
    'iloveyou'
  ];
}

export const URI_ISSUER_PLACEHOLDER: string = '__mfa__';

// 规范 §6.2：issuer 含冒号或为空时用固定占位符建号，再按响应校正（两端逐字一致）
export function planUriIssuer(issuer: string): string {
  return issuer.includes(':') || issuer.length === 0 ? URI_ISSUER_PLACEHOLDER : issuer;
}

export enum BackupErrorCode {
  E_FORMAT = 'E_FORMAT',
  E_VERSION = 'E_VERSION',
  E_METHOD = 'E_METHOD',
  E_STRUCTURE = 'E_STRUCTURE',
  E_PASSWORD = 'E_PASSWORD',
  E_CORRUPT = 'E_CORRUPT',
  E_PAYLOAD = 'E_PAYLOAD',
  E_NORMALIZE = 'E_NORMALIZE'
}

export function backupErrorText(code: BackupErrorCode): string {
  switch (code) {
    case BackupErrorCode.E_FORMAT:
      return '不是本应用备份文件';
    case BackupErrorCode.E_VERSION:
      return '备份版本过新，请升级应用';
    case BackupErrorCode.E_METHOD:
      return '不支持的加密方式';
    case BackupErrorCode.E_STRUCTURE:
      return '备份文件结构异常';
    case BackupErrorCode.E_PASSWORD:
      return '口令错误';
    case BackupErrorCode.E_CORRUPT:
      return '备份文件已损坏或被篡改';
    case BackupErrorCode.E_PAYLOAD:
      return '备份内容异常';
    case BackupErrorCode.E_NORMALIZE:
      return '当前系统不支持口令规范化';
    default:
      return '操作失败，请重试';
  }
}

export class BackupError extends Error {
  readonly code: BackupErrorCode;
  readonly detail: string;

  constructor(code: BackupErrorCode, detail: string = '') {
    super(backupErrorText(code));
    this.name = 'BackupError';
    this.code = code;
    this.detail = detail;
  }
}
