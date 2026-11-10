/**
 * 备份导出编排测试：序列化服务端信封（api 由测试注入，不触网）。
 * 导入无编排层，页面直接调用 `backupApi.importBackup`，因此这里不再覆盖。
 */
import { describe, expect, it } from "bun:test";
import { buildExport } from "../../src/models/backup/exporter";
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
        {
          exportBackup: async () => invalid as unknown as BackupEnvelope,
        },
        "correct horse",
      ),
    ).rejects.toThrow("备份类型不受支持");
  });
});
