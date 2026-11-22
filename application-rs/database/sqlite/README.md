# SQLite 数据库（原 TiDB）

后端已从 TiDB（MySQL 协议）切换到单机 SQLite。本目录存放建库脚本与一次性迁移工具。

## 目录

```
sqlite/
├── account/00-init.sql      # account.db 建表（用户/第三方账号/token）
├── tool/00-init.sql         # tool.db 建表（短链/TOTP）
└── migrate/                 # TiDB → SQLite 一次性迁移（迁移完成后可删除）
    ├── export.sh            # 从 TiDB 只读导出 TSV
    ├── import.py            # TSV → SQLite（重新编号 + 时区转换）
    └── verify.py            # 迁移后一致性校验
```

两个库文件的划分沿用原 TiDB 的 `account` / `tool` 两套 schema；SQLite 没有 schema 概念，
表名已去掉前缀。**库文件不要提交到仓库**（已在 `.gitignore` 忽略）。

## 建库

```bash
mkdir -p /www/data
sqlite3 /www/data/account.db < database/sqlite/account/00-init.sql
sqlite3 /www/data/tool.db    < database/sqlite/tool/00-init.sql
```

`config.toml` 对应配置（`max-connections` 建议 4，SQLite 单写者，连接数多了只会排队）：

```toml
[databases.account]
url = "sqlite:///www/data/account.db"
max-connections = 4
min-connections = 1
acquire-timeout = 5   # 同时作为 SQLite 的 busy_timeout
idle-timeout = 300

[databases.tool]
url = "sqlite:///www/data/tool.db"
max-connections = 4
min-connections = 1
acquire-timeout = 5
idle-timeout = 300
```

`create_if_missing = false`：**库文件不存在时服务启动即失败**，不会静默创建空库。

## 从 TiDB 迁移（一次性）

```bash
cd database/sqlite/migrate

# 1. 导出（只读，凭据走环境变量）
TIDB_HOST=xxx TIDB_USER=xxx TIDB_PASS=xxx ./export.sh

# 2. 导入（目标库需先按上面的「建库」建好）
python3 import.py --dump-dir ./dump \
    --account-db /www/data/account.db \
    --tool-db    /www/data/tool.db

# 3. 校验
python3 verify.py --dump-dir ./dump \
    --account-db /www/data/account.db \
    --tool-db    /www/data/tool.db
```

## 迁移脚本做的三件事

1. **主键重新编号**：TiDB 主键是 `AUTO_RANDOM` 的 64 位无符号数，约一半超过 `i64::MAX`，
   SQLite 的 `INTEGER` 存不下。导入时按 `(created_at, id)` 顺序重新编号为 `1..N`，
   并同步改写 `third_user.user_id` / `access_token.user_id` / `refresh_token.access_token_id`
   / `totp.user_id`。`totp.user_id` 在 tool.db、`user.id` 在 account.db，跨库无法 SQL 关联，
   映射在 `import.py` 进程内维护。
2. **时区**：TiDB 会话时区为 UTC，导出时显式 `SET time_zone = '+00:00'`；导入时按 UTC
   解释并写入 `+08:00` 的 RFC3339 文本，与后端 `Local::now()` 的格式一致。
3. **时间列不设默认值**：SQLite 没有 `ON UPDATE CURRENT_TIMESTAMP`，`created_at` /
   `updated_at` 一律由应用层显式写入。

## 与 TiDB 的行为差异

| 项 | TiDB | SQLite |
|---|---|---|
| 主键 | `AUTO_RANDOM`（64 位无符号、打散） | `INTEGER PRIMARY KEY AUTOINCREMENT`（1..N，永不复用） |
| `updated_at` | `ON UPDATE CURRENT_TIMESTAMP` 自动更新 | 应用层写入，漏写就会停更 |
| 文本比较 | `utf8mb4_unicode_ci`（大小写不敏感） | `BINARY`（大小写敏感） |
| JSON | `json` 类型 + `JSON_SET` | `TEXT` + `json_valid` 约束 + SQLite JSON1 函数 |
| 并发 | 多写者 | WAL + 单写者，`busy_timeout` 兜底 |

## 备份（当前未实现）

**当前没有任何备份机制**，库文件丢失/损坏即数据不可恢复。补备份时最小可用做法：

```bash
# VACUUM INTO 生成一致性快照（WAL 下直接 cp 会丢 -wal 内容）
sqlite3 /www/data/account.db "VACUUM INTO '/tmp/bk/account.db'"
```
