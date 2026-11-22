-- tool.db：工具模块（原 TiDB `tool` schema）
--
-- 用法：sqlite3 /www/data/tool.db < database/sqlite/tool/00-init.sql
--
-- 与 TiDB 的差异同 account/00-init.sql：去 schema 前缀、AUTOINCREMENT 主键、
-- JSON 存 TEXT、时间列存 RFC3339 文本且不设默认值。

PRAGMA journal_mode = WAL;

CREATE TABLE short_url (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    short      TEXT    NOT NULL,
    -- TiDB 侧为可空，但 Rust 侧 `ShortUrl.url` 是非 Option，迁移前已确认无 NULL
    url        TEXT    NOT NULL,
    visit      INTEGER NOT NULL DEFAULT 0,
    created_at TEXT    NOT NULL,
    updated_at TEXT    NOT NULL
);

CREATE UNIQUE INDEX uk_tool_short ON short_url (short);

CREATE TABLE totp (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER NOT NULL,
    username   TEXT    NOT NULL,
    issuer     TEXT,
    config     TEXT    NOT NULL CHECK (json_valid(config)),
    created_at TEXT    NOT NULL,
    updated_at TEXT    NOT NULL,
    sort       INTEGER NOT NULL DEFAULT 0
);

-- `(user_id, sort)` 已覆盖仅按 user_id 的查询，无需再单独建 user_id 索引
CREATE INDEX idx_tool_totp_user_sort ON totp (user_id, sort);
