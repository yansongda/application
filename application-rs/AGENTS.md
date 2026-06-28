# AGENTS.md

## 项目概述

Rust 后端 workspace，提供多因子认证（MFA）服务 API。
使用 Salvo Web 框架、SQLx 原生 SQL 访问 MySQL。

## 仓库结构

```
application-rs/
  application-api/       # HTTP API 二进制入口（src/bin/api.rs）
  application-kernel/    # 核心库：配置、日志、错误/结果类型
  application-database/  # 数据库访问层（MySQL、SQLx）
  application-util/      # HTTP 客户端、第三方平台对接
  database/              # SQL 迁移脚本
```

依赖关系：`application-api -> {kernel, database, util}`，`database -> {kernel, util}`，`util -> kernel`。

## 构建 / 检查 / 测试命令

所有 Rust 命令必须在 `application-rs/` 目录下执行。

```bash
# 检查 / 格式化 / 测试 / 构建
cargo check --all-features
cargo fmt --all -- --check
cargo clippy -- -D warnings
cargo test --all-features
cargo build --release

# Docker 构建
docker build -t app -f Dockerfile-application-api .
```

## CI 流水线（.github/workflows/coding-linter.yml）

推送到 main 或提交 PR 时，后端相关检查包括：

1. `cargo check --all-features`
2. `cargo fmt --all -- --check`
3. `cargo clippy -- -D warnings`

无 `rustfmt.toml` 或 `clippy.toml`，均使用默认规则。

## 代码风格规范

### 格式化

使用默认 `rustfmt` 规则；4 空格缩进，无行尾空格。提交前运行 `cargo fmt --all`。

### Import 组织

顺序如下，各组之间无空行分隔，仅排序：

1. `crate::` 本 crate 内部导入
2. `application_*` 工作区内部 crate 导入
3. 第三方 crate 导入
4. `std` 标准库导入

示例：

```rust
use crate::Pool;
use application_kernel::result::Error;
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use std::time::Instant;
use tracing::{error, info};
```

### 命名约定

| 元素         | 约定               | 示例                          |
|--------------|--------------------|-------------------------------|
| Crate 名称   | `kebab-case`       | `application-kernel`          |
| 模块名       | `snake_case`       | `access_token`、`short_url`   |
| 结构体/枚举  | `PascalCase`       | `AccessToken`、`LoginRequest` |
| 函数名       | `snake_case`       | `fetch`、`update_or_insert`   |
| 常量         | `SCREAMING_SNAKE`  | `MAX_LOG_LENGTH`              |
| 全局静态变量 | `G_` 前缀          | `G_CONFIG`、`G_POOL_MYSQL`    |

### 类型约定

- ID 使用 `u64`；时间戳使用 `DateTime<Local>`
- 数据库 JSON 列使用 `Json<T>`；可空字符串使用 `Option<String>`
- 全局静态变量使用 `LazyLock`；Token 生成使用 `Uuid::now_v7()`

### 错误处理

自定义 `Error` 枚举位于 `application-kernel::result`，配合 `Result<D>` 类型别名。
每个变体包装 `Option<String>`，用于可选的自定义错误消息。
错误消息使用中文，错误码按类别分段：

- 1000 系列：授权认证错误
- 2000 系列：参数校验错误
- 9800 系列：第三方服务错误
- 9900 系列：内部/数据库错误

数据库错误标准模式：`error!()` 记录日志后映射为通用错误。服务层使用 `?` 提前返回或显式 `Err(Error::Variant(None))`。

## 架构分层（application-api）

```
v1/        #[handler] 函数，解析请求，调用 service，返回 Response
service/   业务编排、校验逻辑，调用 database crate
request/   DTO + Validator trait 实现
response.rs  Response<D>、ApiErr、Scribe 实现
```

请求校验通过 `Validator::validate() -> Result<Self::Data>` 完成。

## 数据库层（application-database）

- 原生 SQL + `sqlx::query_as` / `sqlx::query`，不使用 ORM
- 连接池：`LazyLock<HashMap<&str, MySqlPool>>`，通过 `Pool::mysql("account")?` 访问
- 数据库宏自动记录 SQL、参数和耗时

## 日志与异步

- 使用 `tracing` 结构化日志
- 运行时使用 `tokio::main`
- 并发操作使用 `tokio::try_join!`
- 非阻塞日志输出使用 `tracing-appender`

每个数据库操作记录 `Instant::now()` 开始时间和耗时。

## 配置管理

- 运行时配置通过 `config.toml` 或 `APP__*` 环境变量（双下划线嵌套，如 `APP__DATABASES__ACCOUNT__URL`）
- 全局配置 `G_CONFIG: LazyLock<Config>` 位于 `application-kernel::config`
- 禁止提交 `config.toml`，以 `config.toml.example` 为模板

## 测试

- 单元测试使用 `#[cfg(test)] mod tests`；现有覆盖率低，CI 不执行 `cargo test`。
- 遵循模式：构造数据 -> 序列化 -> 断言 JSON 字段。

## 反模式（ANTI-PATTERNS）

- 禁止在生成代码中使用 `.unwrap()` / `.unwrap_err()` / `.expect()`；启动期 fail-fast 除外，统一使用 `Error` 枚举 + `?` 传播。
- 禁止使用 `lazy_static!`；全局静态变量使用 `std::sync::LazyLock`。
- 禁止引入 ORM；数据库层统一使用原生 SQL + `sqlx::query_as` / `sqlx::query`。
- 禁止在日志中记录完整 headers 或 body，尤其是 `Authorization` 头和第三方 API 响应中的密钥/token。
- 禁止提交 `config.toml`、`*.private.*`、密钥、Token、生产连接串。
- 禁止 `#[allow(dead_code)]` 不加注释；若确需保留，需说明理由和清理计划。

## 禁止提交的文件

- `target/`、`.idea/`、`.vscode/`、`config.toml`、`*.private.*`
- 必须提交：`Cargo.lock`

## NOTES

- `application-macro/` 目录已不存在，本文件已移除该条目。
- `middleware.rs` 与 `application-util/src/http.rs` 当前会记录完整 headers，后续需脱敏 `Authorization` 等敏感头。
- 测试覆盖率低，CI 仅执行 `cargo check` / `cargo fmt` / `cargo clippy`，不执行 `cargo test`。
