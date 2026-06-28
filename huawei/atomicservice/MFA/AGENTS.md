# AGENTS.md

## 项目概述

该目录是华为元服务前端工程，当前工程名为 `MFA`，主要使用 ArkTS/ETS。

## 目录结构

```
MFA/
  AppScope/
  entry/
    src/main/ets/      # 主要业务代码
    src/test/          # 本地测试
    src/ohosTest/      # Ohos 测试
  oh-package.json5     # 依赖定义
  oh-package-lock.json5
  build-profile.json5
  hvigorfile.ts
  code-linter.json5    # lint 规则
```

`entry/src/main/ets/` 下常见结构：

- `ability/`：Ability 入口（EntryAbility.ets）
- `pages/`：页面
- `components/`：组件
- `api/`：接口调用
- `models/`：模型
- `utils/`：工具函数
- `themes/`：主题定义
- `types/`：类型定义

## 依赖与配置

- 依赖文件：`oh-package.json5`
- 锁文件：`oh-package-lock.json5`
- 工程配置：`build-profile.json5`、`hvigorfile.ts`
- lint 配置：`code-linter.json5`

已确认的依赖包括：

- `@ohos/axios`
- `@developers/dateformat`

## lint 约束

- lint 主要覆盖 `**/*.ets`
- 忽略目录包括：`src/ohosTest/`、`src/test/`、`src/mock/`、`node_modules/`、`oh_modules/`、`build/`、`.preview/`
- 当前规则集包含性能与 TypeScript 相关推荐规则
- 安全相关规则对不安全加密算法有限制，修改安全或加密相关逻辑时要特别谨慎

## 开发约束

- 新增或修改页面、组件、接口、模型时，优先沿用 `entry/src/main/ets/` 下现有目录组织
- 主题、公共组件、网络请求封装优先复用现有实现，避免重复创建近似能力
- 与后端 API 联动时，接口字段、鉴权语义、错误处理需与后端保持一致
- 未确认工程已有命令前，不凭空引入新的构建或测试流程，优先遵循工程内现有配置文件

## 测试

- 本地测试目录：`entry/src/test/`
- Ohos 测试目录：`entry/src/ohosTest/`
- 修改公共组件、页面跳转、接口调用或运行时模型时，应同步检查相关测试是否需要更新

## 提交约束

- 禁止提交：`build/`、`oh_modules/`、`.hvigor/`、`.idea/`、`.preview/`
- 必须提交：`oh-package-lock.json5`

## 联动开发说明

- 涉及后端接口联动时，同时参考根目录 `AGENTS.md` 与 `application-rs/AGENTS.md`
- 仅修改华为前端时，不需要遵循 Rust 或微信小程序目录下的专属规范

## NOTES

- `entry/src/main/ets/ability/` 目录包含 `EntryAbility.ets`（UIAbility 入口），上表已补充。
- `code-linter.json5` 包含 `@security/no-unsafe-*` 系列规则，修改加密/安全相关逻辑前请先确认不会触发 lint 错误。
- `build-profile.json5` 中的签名配置使用本地绝对路径与明文密码，仅用于本地开发，禁止用于生产。
- 当前仓库 CI 未包含华为前端的构建/lint 检查。
