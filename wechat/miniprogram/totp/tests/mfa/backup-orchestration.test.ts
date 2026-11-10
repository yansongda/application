/**
 * 备份编排测试：导出序列化 / 导入单次调用（api 由测试注入，不触网）。
 */
import { describe, expect, it } from "bun:test";
import { buildExport } from "../../src/models/backup/exporter";
import { runImport } from "../../src/models/backup/importer";
import type { BackupEnvelope } from "../../src/types/backup";

const envelope = (count: number): BackupEnvelope => ({
  format: "application",
  kind: "totp",
  version: 1,
  meta: { created_at: "2026-06-28T14:30:00+08:00", count },
  kdf: { alg: "pbkdf2-sha256", iterations: 600000, salt: "c2FsdA==" },
  cipher: { alg: "aes-256-gcm", nonce: "bm9uY2U=" },
  data: "ZGF0YQ==",
});

describe("backup export orchestration", () => {
  it("serializes_server_envelope_and_reports_meta", async () => {
    const calls: string[] = [];
    const result = await buildExport(
      {
        exportBackup: async (password) => {
          calls.push(password);

          return envelope(3);
        },
      },
      "correct horse",
    );

    expect(calls).toEqual(["correct horse"]);
    expect(result.count).toBe(3);
    expect(result.createdAt).toBe("2026-06-28T14:30:00+08:00");
    expect(JSON.parse(result.text).meta.count).toBe(3);
  });

  it("rejects_invalid_server_envelope", async () => {
    const invalid = { ...envelope(1), kind: "settings" };

    await expect(
      buildExport(
        { exportBackup: async () => invalid as BackupEnvelope },
        "correct horse",
      ),
    ).rejects.toThrow("备份类型不受支持");
  });
});

describe("backup import orchestration", () => {
  it("calls_server_once_with_envelope_and_password", async () => {
    const calls: Array<{ backup: BackupEnvelope; password: string }> = [];
    const input = envelope(4);
    const result = await runImport(
      {
        importBackup: async (backup, password) => {
          calls.push({ backup, password });

          return 4;
        },
      },
      input,
      "passphrase",
    );

    expect(result.imported).toBe(4);
    expect(calls).toHaveLength(1);
    expect(calls[0].backup).toBe(input);
    expect(calls[0].password).toBe("passphrase");
  });
});
