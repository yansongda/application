# PROJECT KNOWLEDGE BASE

**Generated:** 2026-06-28  
**Commit:** 36c8f4a  
**Branch:** main

## OVERVIEW

前后端同仓库维护的 MFA（多因子认证）服务 monorepo。Rust 后端提供 HTTP API，微信/华为前端分别对接微信登录与华为帐号登录，共享同一套后端服务。

核心栈：Rust / Salvo / SQLx / MySQL；微信原生小程序（TypeScript）；华为元服务（ArkTS/ETS）。

## STRUCTURE

```
yansongda-application/
├── application-rs/                 # Rust 后端 workspace
│   ├── application-api/            # HTTP API 二进制入口
│   ├── application-kernel/         # 配置、日志、错误类型
│   ├── application-database/       # 数据库访问层（SQLx + 原生 SQL）
│   ├── application-util/           # 第三方 HTTP 对接（微信/华为）
│   └── database/                   # SQL 迁移脚本
├── wechat/miniprogram/
│   ├── yansongda/                  # 主微信小程序（pnpm）
│   └── totp/                       # TOTP 独立微信小程序（Deno）
└── huawei/atomicservice/MFA/       # 华为元服务（ohpm / Hvigor）
    └── entry/src/main/ets/         # ArkTS 业务代码
```

## WHERE TO LOOK

| 任务 | 入口 | 详情位置 |
|------|------|----------|
| 后端架构/构建/风格 | `application-rs/application-api/src/bin/api.rs` | `application-rs/AGENTS.md` |
| 后端 API 路由 | `application-rs/application-api/src/routes.rs` | `application-rs/AGENTS.md` |
| 后端错误码/配置 | `application-rs/application-kernel/src/result.rs` | `application-rs/AGENTS.md` |
| 微信主小程序开发 | `wechat/miniprogram/yansongda/src/app.ts` | `wechat/miniprogram/yansongda/AGENTS.md` |
| TOTP 微信小程序开发 | `wechat/miniprogram/totp/src/app.ts` | `wechat/miniprogram/totp/AGENTS.md` |
| 华为元服务开发 | `huawei/atomicservice/MFA/entry/src/main/ets/ability/EntryAbility.ets` | `huawei/atomicservice/MFA/AGENTS.md` |
| CI/CD 配置 | `.github/workflows/` | 本文件 COMMANDS / NOTES |

## CODE MAP

| Symbol | Type | Location | Role |
|--------|------|----------|------|
| `main` | function | `application-rs/application-api/src/bin/api.rs:7` | Rust API 启动入口 |
| `App` | struct | `application-rs/application-api/src/lib.rs` | 构建 router 与 listener |
| `api_v1` | function | `application-rs/application-api/src/routes.rs:33` | `/api/v1` 路由聚合 |
| `Response<D>` | struct | `application-rs/application-api/src/response.rs:8` | 统一 API 响应体 + Scribe |
| `ApiErr` | struct | `application-rs/application-api/src/response.rs:61` | `Error` → Salvo 响应包装 |
| `Error` | enum | `application-rs/application-kernel/src/result.rs` | 全局错误枚举（1000/2000/9800/9900） |
| `G_CONFIG` | static | `application-rs/application-kernel/src/config.rs` | 全局运行时配置 |
| `Pool` | struct | `application-rs/application-database/src/lib.rs` | MySQL 连接池管理 |
| `Platform` | enum | `application-rs/application-database/src/account/mod.rs` | 平台标识：wechat/huawei |
| `request` | function | `application-rs/application-util/src/http.rs:27` | 通用第三方 HTTP 请求 |
| `login` | function | `application-rs/application-util/src/wechat.rs` | 微信 jscode2session |
| `token` | function | `application-rs/application-util/src/huawei.rs` | 华为 OAuth token |

## CONVENTIONS

- 跨前后端改动时，分别遵循对应目录下的 `AGENTS.md`，不要用一端规则约束另一端。
- 必须提交的锁文件：`Cargo.lock`、`pnpm-lock.yaml`（yansongda）、`deno.lock`（totp）、`oh-package-lock.json5`（华为）。
- 禁止提交的敏感内容：`config.toml`、`*.private.*`、密钥、Token、密码、生产连接串。
- 禁止提交的构建/IDE 目录：`target/`、`node_modules/`、`miniprogram_npm/`、`oh_modules/`、`.idea/`、`.vscode/`。
- 影响公共 API / 配置 / 数据结构时，需说明兼容策略与迁移方式。
- 尽量小步变更：一次改动聚焦一个问题，避免无关批量格式化。

## ANTI-PATTERNS (THIS PROJECT)

- 不要在日志中记录完整请求/响应头，尤其是 `Authorization` 头。
- 不要硬编码生产密钥、Token、密码；配置通过 `config.toml` 或 `APP__*` 环境变量注入。
- 不要在 Rust 生产代码中随意使用 `.unwrap()` / `.unwrap_err()` / `.expect()`（启动期 fail-fast 除外）。
- 不要引入 ORM；数据库层统一使用 `sqlx` + 原生 SQL。
- 不要提交 `config.toml`、证书密码、本地绝对路径（华为 `build-profile.json5` 中的签名配置需特别注意）。

## UNIQUE STYLES

- **多包管理器并存**：后端 cargo，微信主小程序 pnpm，TOTP 小程序 Deno，华为 ohpm。
- **Rust workspace 使用较新的工具链特性**，依赖使用 `~` 约束。
- **无 ORM 的数据库层**：通过自定义宏（`query_optional!` / `insert!` / `update!` / `delete!`）统一记录 SQL、耗时和参数。
- **微信/华为前端共享同一后端**，但登录方式不同：微信用 `wx.login` code，华为用 HuaweiID authorizationCode。
- **后端无 JWT**：access_token / refresh_token 均为 opaque UUID v7，数据库验证。

## COMMANDS

```bash
# 后端（在 application-rs/ 下执行）
cargo check --all-features
cargo clippy -- -D warnings
cargo fmt --all -- --check
cargo test --all-features
cargo build --release

# 微信主小程序（在 wechat/miniprogram/yansongda/ 下执行）
pnpm i
pnpm biome:check

# TOTP 微信小程序（在 wechat/miniprogram/totp/ 下执行）
deno install
deno task biome:check
deno task typecheck

# 华为元服务：通过 DevEco Studio 或 Hvigor CLI 构建/运行
```

## NOTES

- `application-rs/AGENTS.md` 中已修正：移除不存在的 `application-macro/` 目录；CI 不运行 `cargo test`。
- `wechat/miniprogram/yansongda/` 当前缺失 `pnpm-lock.yaml`（AGENTS.md 要求提交），请检查是否被 gitignore 或未生成。
- 华为 `build-profile.json5` 包含本地签名证书路径与明文密码，仅用于本地开发，禁止用于生产。
- 后端 `middleware.rs` 与 `application-util/src/http.rs` 当前会记录完整 headers，后续需脱敏 `Authorization` 等敏感头。
- 三个前端均无实际业务测试；Rust 后端仅有少量单元测试，CI 不执行测试。
