/**
 * 备份口令校验测试：与服务端一致，不 trim、不做 Unicode 归一化。
 */
import { describe, expect, it } from "bun:test";
import {
  checkExportPassword,
  checkImportPassword,
} from "../../src/models/backup";

describe("export password", () => {
  it("requires_at_least_eight_code_points", () => {
    expect(checkExportPassword("1234567a1").ok).toBe(true);
    expect(checkExportPassword("1234567a").ok).toBe(true);
    expect(checkExportPassword("aB34567").ok).toBe(false);
  });

  it("counts_unicode_code_points", () => {
    // 4 个 emoji = 4 个码点（不是 8 个 UTF-16 单元）
    expect(checkExportPassword("😀😀😀😀").ok).toBe(false);
    expect(checkExportPassword("😀😀😀😀😀😀😀😀").ok).toBe(true);
  });

  it("rejects_surrounding_whitespace", () => {
    for (const password of [" 12345678", "12345678 ", " 12345678 "]) {
      expect(checkExportPassword(password).ok).toBe(false);
    }
  });

  it("rejects_weak_passwords_case_insensitively", () => {
    for (const password of [
      "password1",
      "Password1",
      "PASSWORD1",
      "iloveyou",
    ]) {
      expect(checkExportPassword(password).ok).toBe(false);
    }
  });

  it("rejects_too_long_password", () => {
    expect(checkExportPassword("a".repeat(129)).ok).toBe(false);
    expect(checkExportPassword("a".repeat(128)).ok).toBe(true);
  });

  it("rejects_inconsistent_confirmation", () => {
    expect(checkExportPassword("correct-horse", "correct-horsE").ok).toBe(
      false,
    );
    expect(checkExportPassword("correct-horse", "correct-horse").ok).toBe(true);
    // 省略 confirm 时只校验强度
    expect(checkExportPassword("correct-horse").ok).toBe(true);
  });

  it("reports_mismatch_before_strength", () => {
    expect(checkExportPassword("", "abc")).toEqual({
      ok: false,
      reason: "两次输入的口令不一致",
    });
  });
});

describe("import password", () => {
  it("allows_short_but_not_empty_password", () => {
    expect(checkImportPassword("").ok).toBe(false);
    expect(checkImportPassword("x").ok).toBe(true);
    expect(checkImportPassword("a".repeat(128)).ok).toBe(true);
    expect(checkImportPassword("a".repeat(129)).ok).toBe(false);
  });

  it("does_not_reject_weak_or_whitespace_padded_password", () => {
    // 旧备份可能用短口令 / 带空格口令，导入端只校验可用性
    expect(checkImportPassword("password").ok).toBe(true);
    expect(checkImportPassword(" 12345678 ").ok).toBe(true);
  });
});
