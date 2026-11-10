/**
 * 备份口令校验（导出端强度、导入端可用性）。
 *
 * 与服务端语义保持一致：口令按 UTF-8 原字节参与 PBKDF2，**不 trim、不做 Unicode 归一化**。
 * 因此这里也不归一化；导出时显式拒绝首尾空格，避免用户导出后无法再次输入相同口令。
 */

const MIN_EXPORT_CODE_POINTS = 8;
const MAX_CODE_POINTS = 128;

/** 与服务端一致的弱口令黑名单（仅导出端提示，服务端不强制），按小写比较。 */
const WEAK_PASSWORDS: ReadonlySet<string> = new Set([
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
]);

export type PasswordStrength = { ok: true } | { ok: false; reason: string };

const codePointCount = (text: string): number => {
  return Array.from(text).length;
};

/** 上限检查（导出/导入共用）；未超限返回 `undefined`。 */
const tooLong = (count: number): PasswordStrength | undefined => {
  return count > MAX_CODE_POINTS
    ? { ok: false, reason: `口令最多 ${MAX_CODE_POINTS} 个字符` }
    : undefined;
};

/**
 * 导出端：两次输入一致 → 无首尾空格 → 8–128 个 Unicode 字符 → 非弱口令。
 * `confirm` 省略时跳过一致性校验（供单独校验强度的场景使用）。
 */
export const checkExportPassword = (
  password: string,
  confirm?: string,
): PasswordStrength => {
  if (confirm !== undefined && password !== confirm) {
    return { ok: false, reason: "两次输入的口令不一致" };
  }

  if (password.trim() !== password) {
    return { ok: false, reason: "口令首尾不能包含空格" };
  }

  const count = codePointCount(password);

  if (count < MIN_EXPORT_CODE_POINTS) {
    return { ok: false, reason: `口令至少 ${MIN_EXPORT_CODE_POINTS} 个字符` };
  }

  const max = tooLong(count);

  if (max !== undefined) {
    return max;
  }

  if (WEAK_PASSWORDS.has(password.toLowerCase())) {
    return { ok: false, reason: "口令过弱，请换一个" };
  }

  return { ok: true };
};

/** 导入端：只校验非空与上限（旧备份可能用短口令，保证兼容）。 */
export const checkImportPassword = (password: string): PasswordStrength => {
  const count = codePointCount(password);

  if (count === 0) {
    return { ok: false, reason: "请输入备份口令" };
  }

  return tooLong(count) ?? { ok: true };
};
