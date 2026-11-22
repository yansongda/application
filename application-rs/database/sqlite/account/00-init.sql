-- account.db：账户模块（原 TiDB `account` schema）
--
-- 用法：sqlite3 /www/data/account.db < database/sqlite/account/00-init.sql
--
-- 与 TiDB 的差异（均为有意为之）：
--   1. SQLite 没有 schema，表名去掉 `account.` 前缀
--   2. 主键用 `INTEGER PRIMARY KEY AUTOINCREMENT`：rowid 天然自增，且 id 永不复用
--   3. JSON 列存 TEXT，用 `json_valid` 做兜底校验
--   4. 时间列存 RFC3339 文本（如 `2026-11-09T21:23:29+08:00`），**不设默认值**：
--      SQLite 没有 `ON UPDATE CURRENT_TIMESTAMP`，`updated_at` 一律由应用层写入

PRAGMA journal_mode = WAL;

CREATE TABLE user (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    phone      TEXT,
    config     TEXT CHECK (config IS NULL OR json_valid(config)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX idx_account_phone ON user (phone);

CREATE TABLE third_user (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER NOT NULL DEFAULT 0,
    platform   TEXT    NOT NULL,
    third_id   TEXT    NOT NULL,
    config     TEXT CHECK (config IS NULL OR json_valid(config)),
    created_at TEXT    NOT NULL,
    updated_at TEXT    NOT NULL
);

-- 原 01 脚本本为 UNIQUE，03 迁移到 TiDB 时退化成了普通索引；此处按设计意图补回唯一约束，
-- 避免同一 openid 并发登录产生多条 third_user。
CREATE UNIQUE INDEX uk_third_user_platform_third_id ON third_user (platform, third_id);
CREATE INDEX idx_account_user_id ON third_user (user_id);

CREATE TABLE third_config (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    platform   TEXT    NOT NULL DEFAULT 'wechat',
    third_id   TEXT    NOT NULL,
    config     TEXT    NOT NULL CHECK (json_valid(config)),
    created_at TEXT    NOT NULL,
    updated_at TEXT    NOT NULL
);

CREATE UNIQUE INDEX uk_third_config_platform_third_id ON third_config (platform, third_id);

CREATE TABLE access_token (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id      INTEGER NOT NULL,
    platform     TEXT    NOT NULL DEFAULT 'wechat',
    third_id     TEXT    NOT NULL,
    access_token TEXT    NOT NULL,
    data         TEXT    NOT NULL CHECK (json_valid(data)),
    expired_at   TEXT,
    created_at   TEXT    NOT NULL,
    updated_at   TEXT    NOT NULL
);

CREATE UNIQUE INDEX uk_account_access_token ON access_token (access_token);
CREATE INDEX idx_account_platform_user_id ON access_token (user_id, platform);

CREATE TABLE refresh_token (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    access_token_id INTEGER NOT NULL,
    refresh_token   TEXT    NOT NULL,
    expired_at      TEXT    NOT NULL,
    created_at      TEXT    NOT NULL,
    updated_at      TEXT    NOT NULL
);

CREATE UNIQUE INDEX uk_account_access_token_id ON refresh_token (access_token_id);
CREATE UNIQUE INDEX uk_account_refresh_token ON refresh_token (refresh_token);
