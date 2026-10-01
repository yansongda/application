---
name: release-application-rs
description: 在发布 application-rs Rust 后端 workspace、提升 workspace 版本号、更新 CHANGELOG 或创建 Docker 镜像 tag 时使用
---

# 发布 Application-RS（Rust 后端）

## 概述

本 monorepo 中的 Rust 后端是一个 Cargo workspace，在 tag 推送时通过 GitHub Actions 构建 Docker 镜像。它**不会**发布到 crates.io（`publish = false`）。

**核心原则：** 提升版本号 & 更新 changelog → **创建 PR** → **用户手动合并** → 打 tag & 推送（触发 Docker 构建）。

**⚠️ 必须创建 PR。绝不直推 main。**
**⚠️ 绝不能自动合并 PR。必须由用户审核并手动合并。**

## 前置条件

- Git 工作区干净
- 位于 `main` 分支
- 所有 Rust CI 检查通过（`cargo check`、`cargo fmt --check`、`cargo clippy`）

## 操作流程

### 第 1 步：检查当前状态

```bash
# 必须在 application-rs/ 目录下执行
cd application-rs

# 当前 workspace 版本
grep '^version = ' Cargo.toml

# application-api 最近的 tag
git tag -l 'application-api/*' | sort -V | tail -5

# 检查 git 状态
git status --short
git branch --show-current
```

**Tag 格式：** `application-api/v<VERSION>`（触发 `.github/workflows/build-image.yml`）

**若有未提交改动：** 停下来。先提交或 stash。

### 第 2 步：提升版本号 & 更新 CHANGELOG

**通过分析实际代码 diff 来决定版本提升，而不是只看 commit message。**

```bash
cd application-rs

# 第 1 步：列出上个 tag 之后的提交（仅供参考）
git log <PREV_TAG>..HEAD --oneline

# 第 2 步：查看每个提交的实际改动（这才是关键依据）
git show --stat <commit>

# 第 3 步：审查整体 diff
git diff <PREV_TAG>..HEAD
```

**commit message 只是线索，diff 才是事实。** 一个 `fix:` 提交可能只改了一处注释（无需提升版本），而一个 `chore:` 提交可能引入了新 API（应提升 MINOR）。根据**行为影响**套用 SemVer：

| 改动内容 | 版本提升 | 示例 |
|--------------|-------------|---------|
| 新增面向用户的功能 / 新 API / 新的二进制行为 | **MINOR** | `1.13.0` → `1.14.0` |
| 有行为变化的缺陷修复 | **PATCH** | `1.13.0` → `1.13.1` |
| 纯重构 / 注释修改 / 无行为变化 | **不提升** 或与其他改动合并发布 | 若无用户可见变化，可跳过发版 |
| 破坏性变更（移除 API、改变配置格式） | **MAJOR** | `1.13.0` → `2.0.0` |

**判定流程：**

1. 是否有提交新增了用户可见功能？ → **MINOR**
2. 是否有提交修复了用户实际遇到的问题？ → **PATCH**（若无 MINOR）
3. 是否所有改动都是内部重构 / 清理？ → 若打包发布则 **PATCH**，否则可考虑跳过本次发版
4. 是否有提交破坏向后兼容？ → **MAJOR**

**更新 `application-rs/Cargo.toml`（仅 workspace 根）：**

```toml
[workspace.package]
version = "X.Y.Z"  # 提升这个版本号
```

由于所有子 crate 都使用 `version.workspace = true`，只需更新 workspace 根。务必运行 `cargo update`（或任意构建命令）以重新生成 `Cargo.lock`，然后提交它。

**更新 `application-rs/CHANGELOG.md`：**

遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式：

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- 新功能描述 (#PR) ([commit](https://github.com/yansongda/application/commit/abc123))

### Changed
- 行为变更 (#PR) ([commit](https://github.com/yansongda/application/commit/def456))

### Fixed
- 缺陷修复 (#PR) ([commit](https://github.com/yansongda/application/commit/ghi789))
```

**格式检查清单：**
- [ ] 版本标题：`## [X.Y.Z] - YYYY-MM-DD`（不是 `## vX.Y.Z`）
- [ ] 段落标题首字母大写：`### Added`、`### Changed`、`### Fixed`
- [ ] 每条都带 PR 编号和 commit 链接
- [ ] 新版本加在文件**最上方**

**获取上次发布以来的提交：**
```bash
cd application-rs
git log <PREV_TAG>..HEAD --pretty=format:"- %s ([%h](https://github.com/yansongda/application/commit/%h))"
```

### 第 3 步：校验 Rust 代码质量

创建 PR 之前，确保所有检查通过：

```bash
cd application-rs
cargo check --all-features
cargo fmt --all -- --check
cargo clippy -- -D warnings
```

### 第 4 步：创建 PR

```bash
git checkout -b release/application-rs-vX.Y.Z
git add application-rs/Cargo.toml application-rs/Cargo.lock application-rs/CHANGELOG.md
git commit -m "release(application-rs): vX.Y.Z"
git push origin release/application-rs-vX.Y.Z
gh pr create --title "release(application-rs): vX.Y.Z" --body "Release application-rs vX.Y.Z"
```

**等待用户手动审核并合并 PR。绝不自动合并。**

### 第 5 步：打 Tag & 推送（PR 合并后）

```bash
git checkout main && git pull origin main

# 创建带 application-api 前缀的 tag
git tag application-api/vX.Y.Z
git push origin application-api/vX.Y.Z
```

**⚠️ Tag 格式必须与 workflow 触发条件匹配：**
- workflow `.github/workflows/build-image.yml` 检查 `startsWith(github.ref, 'refs/tags/application-api')`
- tag 格式：`application-api/vX.Y.Z`
- workflow 会自动把 `/` 转换成 `-` 用于 Docker 镜像 tag

### 第 6 步：验证 Docker 构建

- GitHub Actions：https://github.com/yansongda/application/actions
- 确认 `build-image.yml` workflow 运行成功
- 镜像推送到：Aliyun、DockerHub、GitHub Container Registry

## 速查表

| 步骤 | 操作 | 目的 |
|------|--------|---------|
| 1. 检查 | `git status`、`git tag`、查看版本号 | 确认状态干净 |
| 2. 提升 | 编辑 `Cargo.toml`、`CHANGELOG.md` | 更新版本号和 changelog |
| 3. 校验 | `cargo check`、`cargo fmt`、`cargo clippy` | 确保代码质量 |
| 4. PR | 创建 PR，等待合并 | 审核与批准 |
| 5. Tag | `git tag application-api/vX.Y.Z` | 触发 Docker 构建 |
| 6. 验证 | 检查 GitHub Actions | 确认镜像构建完成 |

## 常见错误

**Tag 格式错误**
- **问题：** tag `v1.0.0` 不会触发 workflow
- **修正：** 必须使用 `application-api/v1.0.0`

**提升单个 crate 的版本号**
- **问题：** 直接编辑 `application-api/Cargo.toml`，而它使用的是 `version.workspace = true`
- **修正：** 只提升 workspace 根的 `Cargo.toml`

**忘记运行 Rust 检查**
- **问题：** PR 因 `cargo fmt` 或 `cargo clippy` 报错导致 CI 失败
- **修正：** 创建 PR 前始终运行三项检查

**只看 commit message 决定版本号**
- **问题：** `fix:` 提交可能只改了注释（无需提升版本），而 `chore:` 提交可能新增了 API（应提升 MINOR）
- **修正：** 必须检查 `git show --stat` 和 `git diff` 判断实际行为影响；commit message 只是线索，diff 才是事实

**PR 合并前就打 tag**
- **问题：** tag 指向合并前的 commit
- **修正：** 合并后务必先 `git pull origin main` 再打 tag

**直推 main**
- **问题：** 绕过审核与分支保护
- **修正：** 即使是版本提升也必须创建 PR

## Workspace 结构提醒

```
application-rs/
  Cargo.toml           # Workspace 根 - 在这里提升版本号
  Cargo.lock           # 有变化则提交
  CHANGELOG.md         # 更新发布说明
  application-api/     # 二进制 crate（HTTP API）
  application-database/# 数据库层
  application-kernel/  # 核心类型、配置、错误
  application-macro/   # 过程宏
  application-http/   # HTTP 客户端、第三方集成
```

所有 crate 通过 `version.workspace = true` 共享 workspace 版本号。

## 危险信号

**绝不：**
- 自动合并 PR（必须由用户手动审核）
- 直推 main
- 在 PR 合并前打 tag
- 跳过 `cargo fmt` / `cargo clippy` 检查
- 从有未提交改动的工作区发布
- 使用错误的 tag 格式（`v1.0.0` 而非 `application-api/v1.0.0`）
- 只看 commit message 而不检查实际 diff 就决定版本号

**务必：**
- 创建 PR 前运行所有 Rust 检查
- 只更新 workspace 根的 `Cargo.toml`
- 使用 `application-api/vX.Y.Z` tag 格式
- 打 tag 前等待 PR 合并
