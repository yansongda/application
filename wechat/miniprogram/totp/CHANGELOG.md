# Changelog

本文件遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.2.0] - 2026-11-07

### Added

- 首页对齐华为 MFA 元服务：搜索、标签 / 置顶筛选（底部弹层）、分组视图、拖拽排序（排序模式），扫码或手动输入添加，列表项左滑置顶与删除、点击验证码即复制 (#195)
- 详情页新增验证码大字展示 + 倒计时进度条 + 一键复制，并展示 / 编辑标签与置顶状态，补充验证码位数与摘要算法信息 (#195)
- 新增创建入口页（发行方 / 用户名 / 周期 / 位数 / 算法 / 密钥手动填写）、标签编辑页、个人中心（头像、昵称、Slogan、安全设置）、注销账号页与使用帮助页 (#195)
- 新增防截屏（`setVisualEffectOnCapture`）与应用锁（SOTER 指纹；冷启动、回前台、离开超 1 分钟均校验），配套锁屏组件 (#195)
- 安全设置端云同步：本地为权威，脏标记上行至 `POST /api/v1/users/edit/config/mfa`，换机 / 重装登录后恢复 (#195)
- 新增用户信息接口契约（`/users/detail`、头像 / 昵称 / Slogan 编辑、注销）与用户缓存、视图状态（搜索 / 筛选 / 分组）本地落盘 (#195)
- 端内算码支持后端下发的 `digits`（6~8）与 `algorithm`（SHA1 / SHA256 / SHA512），旧缓存与旧后端响应按 6 位 + SHA1 兜底 (#177)
- 新增 `check:otp-invariants` 静态守卫（`scripts/check-otp-invariants.mjs`）与 `src/otp/README.md`，校验 OTP 库不变量与错误码 (#194)

### Changed

- 端内算码移除 vendored `otpauth@9.5.2`，改用自研零依赖 OTP 库 `src/otp/`（与华为 `@yansongda/otp` 同构），算法与码值零变化；新增 314 项 Bun 测试覆盖 RFC 4226 / 6238 / 4648 向量 (#194)
- 升级 `miniprogram-api-typings` 至 `^5.3.1`，新增 `bun test` 脚本 (#194)

### Removed

- 删除 `src/vendor/`（otpauth ESM 产物）与 `otpauth` 运行时依赖 (#194)

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
