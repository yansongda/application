/**
 * 导入编排：一次请求交给服务端解密并批量写入。
 *
 * 服务端语义（docs/backup-format.md §6）：
 * - 不去重：重复导入会新增重复条目，由用户在列表页删除；
 * - 非事务：任一条目写入失败会返回 9903，可能已写入部分数据，页面需提示刷新核对。
 */
import type { BackupEnvelope } from "types/backup";

export { parseEnvelope as precheck } from "./envelope";

export interface ImportApi {
  importBackup(backup: BackupEnvelope, password: string): Promise<number>;
}

export interface ImportResult {
  imported: number;
}

export const runImport = async (
  api: ImportApi,
  envelope: BackupEnvelope,
  password: string,
): Promise<ImportResult> => {
  const imported = await api.importBackup(envelope, password);

  return { imported };
};
