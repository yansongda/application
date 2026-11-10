/**
 * 备份模块门面：页面只从这里取预检、口令策略与导出编排（4 个符号）。
 * 内部的信封 / 口令 / 编排文件可按需重组而不影响页面。
 * 导入无编排层：服务端一次请求完成解密与批量写入，页面直接调用 `backupApi.importBackup`。
 *
 * 注意：跨目录 import 必须写 `@models/backup/index`，微信运行时不做目录 index 解析。
 */

export { parseEnvelope } from "./envelope";
export type { ExportResult } from "./exporter";
export { buildExport } from "./exporter";
export type { PasswordStrength } from "./password";
export { checkExportPassword, checkImportPassword } from "./password";
