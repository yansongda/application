# Changelog

本文件遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

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
