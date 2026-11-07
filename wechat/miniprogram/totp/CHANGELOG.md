# Changelog

本文件遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added

- 搜索 / 标签 / 置顶 / 分组：缓存与接口契约扩展（`EditTagsRequest` / `EditPinnedRequest`），新增标签编辑页与列表筛选面板
- 新增创建入口页（扫码 / 手动输入）、个人中心页、昵称 / Slogan 编辑页、注销页与使用帮助页（占位注册）
- 新增防截屏（`setVisualEffectOnCapture`）与应用锁（SOTER 指纹）能力及安全设置独立存储键
- 用户信息接口契约（`/users/detail`、头像 / 昵称 / Slogan / 安全设置编辑）与端云同步基础（用户缓存、视图状态存储键）

### Changed

- 端内算码移除 vendored `otpauth@9.5.2`，改用自研零依赖 OTP 库 `src/otp/`（与华为 `@yansongda/otp` 同构），算法与码值零变化；新增 242 项 Bun 测试覆盖 RFC 4226 / 6238 / 4648 向量

### Removed

- 删除 `src/vendor/`（otpauth ESM 产物）与 `otpauth` 运行时依赖

## [1.1.0] - 2026-09-07

### Added

- TOTP 验证码改为本地离线计算，引入 otpauth 本地生成验证码，无需每次请求后端 (#162)

### Changed

- 移除 clock_offset 时钟校准，取码与倒计时改用本地时间 (#163)
- 包管理器由 Deno 迁移至 Bun (#162)

## [1.0.1] - 2026-08-29

### Fixed

- 编辑提供商/账号页面对 URL 参数进行 decodeURIComponent，修复中文回显为 urlencode 乱码 (#159)
- 首页登录与详情页加载增加 loading 提示，并统一为悬浮 Toast，避免与列表加载提示重复 (#159)
- 修复删除确认弹框按钮异色边框，删除/取消按钮改用 TDesign 内置主题与变体 (#159)

## [1.0.0] - 2026-06-28

### Added

- TOTP 安全码小程序首次发布
- 支持 TOTP（基于时间的一次性密码）生成与展示
- 支持添加、编辑、删除 TOTP 条目
- 支持按 issuer 和 username 分组管理
- 支持拖拽排序功能
- 支持微信登录与 access token 自动刷新
- 使用 Deno 作为包管理器
- 集成 TDesign 小程序组件库
