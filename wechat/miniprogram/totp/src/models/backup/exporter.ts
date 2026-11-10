/**
 * 导出编排：调用服务端加密接口，把返回的信封序列化为可保存 / 分享的文本。
 * 条目读取、校验与加密全部在服务端完成；前端不再持有明文打包结果。
 */
import type { BackupEnvelope } from "types/backup";
import { validateEnvelope } from "./envelope";

export interface ExportApi {
  exportBackup(password: string): Promise<BackupEnvelope>;
}

export interface ExportResult {
  /** 可直接写文件 / 复制到剪贴板的 JSON 文本。 */
  text: string;
  count: number;
  /** 信封 meta.created_at（带时区偏移），页面按本地时间显示。 */
  createdAt: string;
  envelope: BackupEnvelope;
}

export const buildExport = async (
  api: ExportApi,
  password: string,
): Promise<ExportResult> => {
  // 服务端响应也走一次预检：避免后端升级 / 代理篡改后把异常信封落成文件
  const envelope = validateEnvelope(await api.exportBackup(password));

  return {
    text: JSON.stringify(envelope, null, 2),
    count: envelope.meta.count,
    createdAt: envelope.meta.created_at,
    envelope,
  };
};
