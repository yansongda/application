# AGENTS.md

## 项目概述

该目录是微信小程序前端，使用 TypeScript 与微信小程序原生目录结构，包管理器固定为 `pnpm`。

小程序工程根目录为 `wechat/miniprogram/yansongda/`，其中真正的小程序源码位于 `src/`（由 `project.config.json` 中 `miniprogramRoot: "src/"` 指定）。

## 目录结构

```
wechat/miniprogram/yansongda/
  src/                         # 小程序业务代码（miniprogramRoot）
  package.json                 # 前端脚本与依赖
  pnpm-lock.yaml               # pnpm 锁文件（必须提交）
  biome.json                   # 格式化与 lint 配置
  tsconfig.json                # TypeScript 配置
  project.config.json          # 微信开发者工具配置
  project.private.config.json  # 个人本地配置（不提交）
  CHANGELOG.md
  .gitignore
```

`src/` 常见子目录：

- `src/pages/`：页面
- `src/components/`：组件
- `src/api/`：接口调用
- `src/utils/`：工具函数
- `src/types/`：类型声明
- `src/constant/`：常量定义
- `src/models/`：数据模型
- `src/custom-tab-bar/`：自定义 tabBar
- `src/images/`：静态图片资源
- `src/miniprogram_npm/`：微信开发者工具构建的 npm 产物（不提交）

## 路径别名

`tsconfig.json` 中已配置以下别名（基于工程根目录）：

- `@api/*`       → `src/api/*`
- `@utils/*`     → `src/utils/*`
- `@constant/*`  → `src/constant/*`
- `@models/*`    → `src/models/*`
- `@components/*`→ `src/components/*`
- `tdesign-miniprogram/*` → `src/miniprogram_npm/tdesign-miniprogram/*`

新增源码目录时，如需暴露给业务层 import，请同步更新 `tsconfig.json` 的 `paths`。

## 构建 / 检查命令

所有命令在 `wechat/miniprogram/yansongda/` 目录下执行，必须使用 `pnpm`：

```bash
pnpm i
pnpm biome:check
pnpm biome:fix
pnpm biome:fix-unsafe
```

## 代码风格规范

- 使用 `biome` 做格式化与 lint，配置文件为 `wechat/miniprogram/yansongda/biome.json`
- `biome` 覆盖范围以 `biome.json` 中的 `files.includes` 为准，并排除 `src/miniprogram_npm/**/*`
- 默认使用空格缩进，JavaScript/TypeScript 字符串使用双引号
- 提交前优先运行 `pnpm biome:check`，需要自动修复时运行 `pnpm biome:fix`

## 开发约束

- 新增页面、组件、接口、工具函数时，优先沿用 `src/` 下现有目录组织
- 类型声明优先放在 `src/types/`
- 与后端 API 对接时，字段命名和含义应与后端保持一致，避免前端自行发明新语义
- 修改公共常量、接口模型或页面交互时，尽量保持微信小程序现有用法一致，避免无关重构

## CI 与提交流程

- 前端 CI 检查为：`pnpm i && pnpm biome:check`
- 禁止提交：`node_modules/`、`src/miniprogram_npm/`、`project.private.config.json`、`.idea/`、`.vscode/`
- 必须提交：`pnpm-lock.yaml`

## 联动开发说明

- 涉及后端接口联动时，同时参考 `application-rs/AGENTS.md`
- 仅修改微信前端时，不需要遵循 Rust 后端的代码风格和构建命令

## NOTES

- 当前目录下未见 `pnpm-lock.yaml`，但 AGENTS.md 要求必须提交；请确认是否已生成并纳入版本控制。
- 主小程序与 `totp` 小程序共享大量工具/类型/模型代码，但当前无正式共享包，分别独立维护。
