# AGENTS.md

## 项目概述

该目录是「TOTP安全码」微信小程序前端，使用 TypeScript 与微信小程序原生目录结构。**包管理器固定为 Deno**（非 pnpm/npm/yarn）。

小程序工程根目录为 `wechat/miniprogram/totp/`，其中真正的小程序源码位于 `src/`（由 `project.config.json` 中 `miniprogramRoot: "src/"` 指定）。

## 目录结构

```
wechat/miniprogram/totp/
  src/                         # 小程序业务代码（miniprogramRoot）
  package.json                 # 脚本定义与依赖声明
  deno.lock                    # Deno 锁文件（必须提交）
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

- **包管理器**：Deno（不是 pnpm）
- **锁文件**：`deno.lock`（必须提交）
- **安装依赖**：`deno install`
- **依赖解析**：Deno 通过 `package.json` 的 `dependencies` / `devDependencies` 自动创建 `node_modules/` 并保持 `deno.lock` 同步

## 构建 / 检查命令

所有命令在 `wechat/miniprogram/totp/` 目录下执行，使用 `deno task`：

```bash
deno install                    # 安装依赖（首次或依赖变更后）
deno task biome:check           # 格式化与 lint 检查
deno task biome:fix             # 自动修复
deno task biome:fix-unsafe      # 自动修复（含不安全修复）
deno task typecheck             # TypeScript 类型检查（tsc --noEmit）
```

## 代码风格规范

- 使用 `biome` 做格式化与 lint，配置文件为 `wechat/miniprogram/totp/biome.json`
- `biome` 覆盖范围以 `biome.json` 中的 `files.includes` 为准（`src/**/*`），并排除 `src/miniprogram_npm/**/*`
- 默认使用空格缩进，JavaScript/TypeScript 字符串使用双引号
- 提交前优先运行 `deno task biome:check`，需要自动修复时运行 `deno task biome:fix`

## 开发约束

- 新增页面、组件、工具函数时，优先沿用 `src/` 下现有目录组织
- 类型声明优先放在 `typings/`
- 与后端 API 对接时，字段命名和含义应与后端保持一致，避免前端自行发明新语义
- 修改公共常量、接口模型或页面交互时，尽量保持微信小程序现有用法一致，避免无关重构

## CI 与提交流程

- 前端 CI 检查为：`deno install && deno task biome:check && deno task typecheck`
- 禁止提交：`node_modules/`、`src/miniprogram_npm/`、`project.private.config.json`、`.idea/`、`.vscode/`
- 必须提交：`deno.lock`

## 联动开发说明

- 涉及后端接口联动时，同时参考 `application-rs/AGENTS.md`
- 仅修改微信前端时，不需要遵循 Rust 后端的代码风格和构建命令
