# Changelog

本文件遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.14.0] - 2026-06-24

### Added

- 实现微信 access token 自动刷新机制：登录后保存 access_token / refresh_token / expired_in 令牌束，支持在 1000/1001/1002/1004 等认证错误时自动刷新并重试原请求 (#139)
- 增加刷新并发去重：同一时刻仅触发一次刷新，其它请求等待同一结果
- 刷新失败时弹出模态框引导用户重新登录

### Fixed

- 修复头像编辑页从本地缓存读取用户信息导致的显示异常，改为调用 user.detail() 并补充错误提示 (#141)
- 修复 HTTP query 参数拼接未过滤空值的问题，改用 URLSearchParams 构建查询串
- 修复 token 过期重试标记在部分场景下丢失的问题，使用显式 isRetry 参数防止无限循环
- 多处健壮性增强：用户资料编辑、TOTP 详情、统一错误码处理等

## [1.13.1] - 2026-05-15

### Fixed

- 重写 TOTP 排序交互并预加载 icon 字体 (#136)

### Changed

- 将小程序源码迁移至 miniprogram/yansongda 子目录 (#134)

## [1.13.0] - 2026-05-13

### Added

- TOTP 列表拖拽排序交互 (#131)
- TOTP API 增加排序参数与类型定义

### Changed

- 调整主题色与全局样式

## [1.12.0] - 2026-05-13

### Added

- 增加多平台多应用功能 (#94)
