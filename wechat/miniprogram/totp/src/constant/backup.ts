/**
 * 后端加密备份接口常量（契约见 application-rs/docs/backup-format.md）。
 * 全部契约常量集中在本文件，与后端一一对应，避免前后端规则漂移；
 * 前端只做结构预检，加解密全部由服务端完成。
 */
const PATH = {
  EXPORT: "/api/v1/backup/export",
  IMPORT: "/api/v1/backup/import",
};

/** 信封格式标识（后端 `service::backup::FORMAT`）。 */
const FORMAT = "application";
/** 当前微信端只消费 TOTP 备份。 */
const KIND = "totp";
/** 信封版本（v1）。 */
const VERSION = 1;
/** 服务端单类备份条目上限（`service::backup::MAX_ITEMS`，导出/导入共用）。 */
const MAX_ITEMS = 50;
/** 信封 `data` 字段字符上限（后端 `MAX_DATA_LEN`，512 KiB）。 */
const MAX_DATA_CHARS = 512 * 1024;
/**
 * 备份文本整体字符上限：后端 `max_size(512 * 1024)` 限的是**整个请求体**，
 * 导入时 body = data + kdf/cipher/meta + JSON 转义开销，因此文本总长必须单独卡住。
 */
const MAX_ENVELOPE_TEXT_CHARS = 512 * 1024;
/** 复制到剪贴板的安全上限（远小于请求体上限，避免系统剪贴板截断）。 */
const CLIPBOARD_MAX_CHARS = 65536;

export {
  CLIPBOARD_MAX_CHARS,
  FORMAT,
  KIND,
  MAX_DATA_CHARS,
  MAX_ENVELOPE_TEXT_CHARS,
  MAX_ITEMS,
  PATH,
  VERSION,
};
