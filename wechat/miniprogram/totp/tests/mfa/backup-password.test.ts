/**
 * 备份口令校验测试：与服务端一致，不 trim、不做 Unicode 归一化。
 */
import { describe, expect, it } from "bun:test";
import {
  checkExportPassword,
  checkImportPassword,
} from "../../src/models/backup/password";

describe("backup password", () => {
  it("export_requires_at_least_eight_code_points", () => {
    expect(checkExportPassword("1234567").ok).toBe(false);
    expect(checkExportPassword("12345678").ok).toBe(false);
    expect(checkExportPassword("1234567a").ok).toBe(true);
  });

  it("export_counts_unicode_code_points", () => {
    // 4 个 emoji = 4 个码点（不是 8 个 UTF-16 单元）
    expect(checkExportPassword("😀😀😀😀").ok).toBe(false);
    expect(checkExportPassword("😀😀😀😀😀😀😀😀").ok).toBe(true);
  });

  it("export_rejects_surrounding_whitespace", () => {
    for (const password of [" 12345678", "12345678 ", " 12345678 "]) {
      expect(checkExportPassword(password).ok).toBe(false);
    }
  });

  it("export_rejects_weak_and_too_long", () => {
    expect(checkExportPassword("password1").ok).toBe(false);
    expect(checkExportPassword("a".repeat(129)).ok).toBe(false);
    expect(checkExportPassword("a".repeat(128)).ok).toBe(true);
  });

  it("import_allows_short_but_not_empty_password", () => {
    expect(checkImportPassword("").ok).toBe(false);
    expect(checkImportPassword("x").ok).toBe(true);
    expect(checkImportPassword("a".repeat(128)).ok).toBe(true);
    expect(checkImportPassword("a".repeat(129)).ok).toBe(false);
  });
});
