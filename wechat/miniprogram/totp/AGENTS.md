# AGENTS.md

## 项目概述

该目录是「TOTP安全码」微信小程序前端，使用 TypeScript 与微信小程序原生目录结构。**包管理器固定为 Bun**（非 pnpm/npm/yarn/deno）。

小程序工程根目录为 `wechat/miniprogram/totp/`，其中真正的小程序源码位于 `src/`（由 `project.config.json` 中 `miniprogramRoot: "src/"` 指定）。

## 目录结构

```
wechat/miniprogram/totp/
  src/                         # 小程序业务代码（miniprogramRoot）
  package.json                 # 脚本定义与依赖声明
  bun.lock                     # Bun 锁文件（必须提交）
  biome.json                   # 格式化与 lint 配置
  tsconfig.json                # TypeScript 配置
  project.config.json          # 微信开发者工具配置
  project.private.config.json  # 个人本地配置（不提交）
  typings/                     # 自定义类型声明
  .gitignore
```

`src/` 常见子目录：

- `src/pages/`：页面
- `src/components/`：组件
- `src/utils/`：工具函数
- `src/miniprogram_npm/`：微信开发者工具构建的 npm 产物（不提交）

## 包管理与依赖

- **包管理器**：Bun（不是 pnpm）
- **锁文件**：`bun.lock`（必须提交）
- **安装依赖**：`bun install`
- **依赖解析**：Bun 通过 `package.json` 的 `dependencies` / `devDependencies` 自动创建 `node_modules/` 并保持 `bun.lock` 同步

## 构建 / 检查命令

所有命令在 `wechat/miniprogram/totp/` 目录下执行，使用 `bun run`：

```bash
bun install                     # 安装依赖（首次或依赖变更后）
bun run biome:check             # 格式化与 lint 检查
bun run biome:fix               # 自动修复
bun run biome:fix-unsafe        # 自动修复（含不安全修复）
bun run typecheck               # TypeScript 类型检查（tsc --noEmit）
bun run test                    # 全部 Bun 测试（tests/）
bun run check:otp-invariants    # OTP 不变量静态守卫
```

## 代码风格规范

- 使用 `biome` 做格式化与 lint，配置文件为 `wechat/miniprogram/totp/biome.json`
- `biome` 覆盖范围以 `biome.json` 中的 `files.includes` 为准（`src/**/*`），并排除 `src/miniprogram_npm/**/*`
- 默认使用空格缩进，JavaScript/TypeScript 字符串使用双引号
- 提交前优先运行 `bun run biome:check`，需要自动修复时运行 `bun run biome:fix`

## 开发约束

- 新增页面、组件、工具函数时，优先沿用 `src/` 下现有目录组织
- 类型声明优先放在 `typings/`
- 与后端 API 对接时，字段命名和含义应与后端保持一致，避免前端自行发明新语义
- 修改公共常量、接口模型或页面交互时，尽量保持微信小程序现有用法一致，避免无关重构

## 加密备份模块（后端 API）

- 加解密全部由服务端完成（`POST /api/v1/backup/export|import`，`kind=totp`），契约见 `application-rs/docs/backup-format.md`；前端**不得**重新引入端内 PBKDF2 / AES-GCM 实现。
- 分层：
  - `src/constant/backup.ts` / `src/types/backup.d.ts` —— 信封常量与类型（字段名与后端 snake_case 保持一致）。
  - `src/api/backup.ts` —— 两个接口封装与后端错误码（2023~2028 / 9903 / 9908）文案映射；备份请求超时 15s。
  - `src/models/backup/` —— 业务编排：`envelope.ts`（无口令结构预检）、`password.ts`（导出强度 / 导入可用性，**不 trim、不做 NFC**）、`exporter.ts` / `importer.ts`（api 由调用方注入，便于单测）。
- 不变量：
  - 口令/密文不得进 logger / storage；口令只存在于页面内存与请求体，`onHide/onUnload` 清空。
  - 导出前应用锁门禁：仅 `SUCCESS` / `NO_CREDENTIAL` 放行，`SKIPPED` 必须拒绝。
  - 服务端上限 50 条；导入**不去重**、非事务（失败可能已写入部分条目，以 `syncFromRemote` 结果为准）。
  - 文件通道只落 `src/utils/backup-file.ts`（`writeBackupFile` / `shareBackupFile` / `readBackupFileFromChat`），文件名后缀沿用 `.mfa`。
  - 测试放 `tests/mfa`（预检 / 口令 / 编排 / 时间解析），不得依赖端内加密向量。

## CI 与提交流程

- 前端 CI 检查为：`bun install && bun run biome:check && bun run typecheck`
- 禁止提交：`node_modules/`、`src/miniprogram_npm/`、`project.private.config.json`、`.idea/`、`.vscode/`
- 必须提交：`bun.lock`

## 联动开发说明

- 涉及后端接口联动时，同时参考 `application-rs/AGENTS.md`
- 仅修改微信前端时，不需要遵循 Rust 后端的代码风格和构建命令

## NOTES

- 与 `yansongda` 主小程序共享 `utils/error.ts`、`utils/logger.ts`、`utils/string.ts`、`models/error.ts`、`types/http.d.ts` 等代码，但当前无正式共享包，分别独立维护。
- 当前 CI 已接入 `bun run biome:check`、`bun run typecheck`、`bun run test`（`tests/`）与 `bun run check:otp-invariants`（不变量静态守卫）。
- `src/otp/` 为自研零依赖 OTP 库（对照 ohos-otp / 华为 `@yansongda/otp` 的分层与契约），`utils/totp.ts` 是唯一业务调用点；API、不变量、错误码与覆盖边界见 `src/otp/README.md`。
- `src/otp/` 相关 import 必须显式指向 `../otp/index`（禁止写 `../otp` 目录），微信运行时不做目录 index 解析。
- 业务 OTP 解析/生成只经 `utils/totp-uri.ts` / `utils/totp.ts`，页面与组件不得直接 import `src/otp/`。
- 新增纯逻辑测试放 `tests/mfa/`。
- 不要重新引入 `otpauth` 或任何运行时密码学依赖；哈希原语在 `src/otp/internal/sha{1,256,512}.ts`，SHA-512 必须用 hi/lo 半字（禁止 BigInt，老设备兼容）。
- `src/otp` 关键不变量：全库无日志、`Secret.toJSON()` 脱敏、`verify` 扫满窗口、取模只在 `digits.format`、`internal/*` 不进 barrel（测试经深路径 import）。
