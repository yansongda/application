/**
 * `src/backup` 的公开入口（barrel）：只聚合**纯库**模块（零业务依赖）。
 *
 * 约束（由 scripts/check-otp-invariants.mjs 静态守卫）：
 * - 本目录不得 import `../api` / `../pages` / `../utils` / `../models` / `../types`；
 * - 唯一允许的跨目录依赖是 `../otp`（复用 SHA-256 / HMAC 与 Base32 严格校验）。
 *
 * 业务编排（导出 / 导入）在 `src/models/backup/`，不属于本库，不进 barrel。
 */
export { type AesGcmResult, aesGcmDecrypt, aesGcmEncrypt } from "./aes-gcm";
export { decodeBase64Strict, encodeBase64 } from "./base64";
export {
  checkPasswordStrength,
  computeKcv,
  type DecryptResult,
  type DeriveResult,
  decryptEnvelope,
  type EncryptContext,
  type EncryptResult,
  encryptEnvelope,
  normalizePassword,
  type PasswordStrength,
  type RandomBytes,
  utf8ToBytes,
} from "./crypto";
export {
  type Envelope,
  type EnvelopeKey,
  type EnvelopeMeta,
  type EnvelopeSource,
  type ParseEnvelopeResult,
  parseEnvelope,
  stringifyEnvelope,
} from "./envelope";
export {
  type BackupItem,
  type InvalidItem,
  normalizeSecret,
  type ParsePayloadResult,
  parsePayload,
  type SanitizeResult,
  sanitizeItem,
  stringifyPayload,
} from "./payload";
export {
  Pbkdf2AbortedError,
  type Pbkdf2Hooks,
  pbkdf2Sha256,
  pbkdf2Sha256Async,
} from "./pbkdf2";
export {
  AAD,
  type BackupAlgorithm,
  BackupError,
  BackupErrorCode,
  backupErrorMessage,
  DEFAULT_ITERATIONS,
  FORMAT,
  IV_BYTES,
  KCV_BYTES,
  KCV_LABEL,
  KEY_BYTES,
  MAX_CIPHERTEXT_BYTES,
  MAX_ITEMS,
  MAX_ITERATIONS,
  MAX_TAGS_PER_ITEM,
  METHOD,
  MIN_ITERATIONS,
  MIN_PASSWORD_CODE_POINTS,
  SALT_BYTES,
  TAG_BYTES,
  VERSION,
  WEAK_PASSWORDS,
} from "./spec";
