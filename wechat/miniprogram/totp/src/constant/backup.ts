/**
 * 后端加密备份接口常量（契约见 application-rs/docs/backup-format.md）。
 * 信封标识、版本与条目上限必须与后端保持一致；前端只做结构预检，加解密全部由服务端完成。
 */
const PATH = {
  EXPORT: "/api/v1/backup/export",
  IMPORT: "/api/v1/backup/import",
};

/** 信封格式标识（后端固定值）。 */
const FORMAT = "application";
/** 当前微信端只消费 TOTP 备份。 */
const KIND = "totp";
/** 信封版本（v1）。 */
const VERSION = 1;
/** 服务端单类备份条目上限（导出/导入共用）。 */
const MAX_ITEMS = 50;

export { FORMAT, KIND, MAX_ITEMS, PATH, VERSION };
