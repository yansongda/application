# SQLite 数据库（原 TiDB）

后端已从 TiDB（MySQL 协议）切换到单机 SQLite。本目录存放建库脚本。

## 目录

```
sqlite/
├── account/00-init.sql      # account.db 建表（用户/第三方账号/token）
└── tool/00-init.sql         # tool.db 建表（短链/TOTP）
```

两个库文件的划分沿用原 TiDB 的 `account` / `tool` 两套 schema；SQLite 没有 schema 概念，
表名已去掉前缀。**库文件不要提交到仓库**（已在 `.gitignore` 忽略 `*.db` 与 `/data/`、`/prod/`、`/test/`）。

从 TiDB 抽数的一次性迁移脚本仅用于 2026-11 的那次切换，用完即删，不再保留在仓库里。

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

`create_if_missing = false`：不会静默创建空库。库文件缺失时服务仍能启动，但首个查询会失败并返回
`9901`/`9902`。

## 部署布局

`docker-compose.yml` 按环境把宿主机目录挂进去（库目录为每个环境独立的 `data/` 子目录，需可写，且**不要**用 `:ro`；
`config.toml` 与库目录分离，单独只读挂载）：

```
application-rs/prod/data/{account.db,tool.db} ->  /www/data          (api)
application-rs/prod/config.toml               ->  /www/config.toml  (api, ro)
application-rs/test/data/{account.db,tool.db} ->  /www/data          (api-test)
application-rs/test/config.toml               ->  /www/config.toml  (api-test, ro)
```

容器 `WORKDIR=/www`，后端固定读 `./config.toml`，所以配置文件必须挂到 `/www/config.toml`；
`url` 写成 `sqlite:///www/data/*.db` 才能对上 `/www/data` 挂载点。

**静默坑**：宿主机 `prod/config.toml` 不存在时，docker 会把该路径建成**同名目录**，后端读不到配置后
回落默认值 —— `databases` 为空 map，服务能启动但所有接口返回 `9901`（不是启动报错）；
`prod/data` 不存在时 docker 会以 root 建空目录，库文件缺失同样是 `9901`/`9902`。部署前先建目录并确认：

```bash
mkdir -p prod/data test/data
ls -l prod/config.toml prod/data/account.db prod/data/tool.db
docker compose exec api ls -l /www/config.toml /www/data
```

## 迁移时做过什么（备查）

1. **主键重新编号**：TiDB 主键是 `AUTO_RANDOM` 的 64 位无符号数，约一半超过 `i64::MAX`，
   SQLite 的 `INTEGER` 存不下。导入时按 `(created_at, id)` 顺序重新编号为 `1..N`，
   并同步改写 `third_user.user_id` / `access_token.user_id` / `refresh_token.access_token_id`
   / `totp.user_id`。
2. **时区**：TiDB 会话时区为 UTC，导入时按 UTC 解释并写入 `+08:00` 的 RFC3339 文本，
   与后端 `Local::now()` 的格式一致；时间列的**绝对时刻**保持不变（`expired_at` 不漂移）。
3. **无归属数据**：生产环境有 18 条 `totp` 行的 `user_id` 已无对应 `user`（2024 年 PG 时期遗留），
   重新编号后无法映射，已在迁移时排除并单独留档。
4. **登录态未迁移**：`access_token` / `refresh_token` 两张表清空未导入（历史 token 无需保留），
   切换后客户端统一重新登录；微信/华为 SDK 均为静默登录，用户无感。TOTP 本地缓存与本地算码不受影响。

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
