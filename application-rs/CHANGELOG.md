## [1.18.0] - 2026-06-25

### Added

- feat(auth): 新增认证错误码：access_token 过期（1004）、refresh_token 无效（1005）、refresh_token 过期（1006）(#140) ([8f9e59f](https://github.com/yansongda/application/commit/8f9e59f))

### Changed

- refactor(auth): 调整 access_token 过期语义，`expired_at` 为空时视为已过期，不再对微信 access_token 做永不过期特殊处理 (#140) ([8f9e59f](https://github.com/yansongda/application/commit/8f9e59f))

## [1.17.0] - 2026-05-13

### Added

- feat(totp): 添加 TOTP 排序功能 (#128) ([aa93ed5](https://github.com/yansongda/application/commit/aa93ed5))

## [1.16.1] - 2026-05-13

### Changed

- refactor(database): 统一数据库查询使用 macros.rs 宏 (#126) ([76c565b](https://github.com/yansongda/application/commit/76c565b))

## [1.16.0] - 2026-05-08

### Fixed

- fix: 移除所有 unwrap() 调用，改用安全的错误处理 (#122) ([60bf0b0](https://github.com/yansongda/application/commit/60bf0b0))

### Changed

- refactor: 代码库质量改进 (#124) ([b035d38](https://github.com/yansongda/application/commit/b035d38))
- refactor(http): 移除 #[serde(untagged)]，改为自定义反序列化 (#123) ([c6fc467](https://github.com/yansongda/application/commit/c6fc467))
- refactor: 重命名 rs-application/ 为 application-rs/ 以对齐 monorepo 目录规范 ([2fd71ce](https://github.com/yansongda/application/commit/2fd71ce))
- docs: add Chinese agent guide for repository workflows ([01bce0a](https://github.com/yansongda/application/commit/01bce0a))

## v1.15.1

### added

- feat: API 响应体中增加 request_id (#121)

### optimize

- optimize: 使用并发执行优化用户注销流程 (#118)
- optimize: 对入参和出参响应内容长度判断，大于1K的部分使用省略号代替，防止内存溢出 (#119)

## v1.15.0

### fixed

- fix: 修复更新用户头像等配置时未处理数据库错误的问题 (#115)

### chore

- chore: axum 替换为 salvo (#114)

## v1.14.1

### added

- feat: 增加注销用户接口 (#108)

### optimized

- optimize: 优化修改用户头像入参校验规则 (#108)

## v1.14.0

### added

- feat: 增加华为元服务 (#97)

## v1.13.2

### optimized

- optimize: 优化 token 的过期时间计算方式 (#99)

## v1.13.1

### fixed

- fix: 修正 refresh_token 访问 url (#98)

## v1.13.0

### optimized

- optimize: 完善 access-token 认证机制 (#97)

## v1.12.2

### optimized

- optimize: 优化 http 请求公共类 (#96)

## v1.12.1

### optimized

- optimize: 删除与优化兼容性代码 (#95)

## v1.12.0

### added

- feat: 增加多平台多应用功能 (#94)

## v1.11.2

### optimized

- optimize: 优化配置文件 (#93)

### chore

- chore: 优化 ci 文件与镜像存储 (#93)

## v1.11.1

### perf

- perf: 优化 clone() 相关代码，提升性能 (#92)

## v1.11.0

### chore

- chore: 迁移到 tidb cloud (#90)

## v1.10.1

### fixed

- fix(frontend): 修复 TOTP 页面在首次进入页面没有自动刷新的问题 (#87, #88)

### optimized

- optimize(backend): 优化后端日志记录 (#86)

## v1.10.0

### changed

- change(frontend): Api 路径去掉 miniprogram 前缀
- change(backend): 后端数据库规划调整
- optimize(backend): 后端架构优化调整

## v1.9.0

### perf

- perf(frontend): 抽离 totp 的 item 组件提升性能 (#84)

### changed

- change(frontend): 修改请求域名 (#84)

## v1.8.2

### optimized

- optimize(frontend): 优化输入框与显示框的最大现实字符数 (#83)

## v1.8.1

### optimized

- optimize: 优化接口及界面参数长度限定 (#82)

## v1.8.0

### changed

- delete(backend): 去掉通用 TOTP 编辑 API (#80)

### optimized

- optimize(frontend): 优化 totp 页面查看与编辑交互体验 (#80)

### refactor

- refactor(backend): 重构 TOTP 相关 API (#80)

## v1.7.0

### added

- feat(backend): 增加用户相关编辑 API (#79)

### fixed

- fix(backend): 修复新用户 token 未与 user 表正确关联的问题 (#79)

### changed

- delete(backend): 去掉通用用户编辑 API (#79)

### optimized

- optimize(frontend): 优化用户查看与编辑交互体验 (#79)
- optimize(frontend): 去掉 totp 页面非必要代码 (#79)

## v1.6.0

### changed

- change(backend): 更改 url，将 /api/v1 更改为 /api/v1/miniprogram/(#75)
- change(frontend-wechat-miniprogram): 适配后端更改(#75)

### added

- chore: 支持多平台底座(#75)

## v1.5.3

### chore

- chore(backend): 将 logger 独立，优化代码结构(#71)

## v1.5.2

### optimized

- optimize(backend): 优化存储在数据库的认证信息(#70)

## v1.5.1

### chore

- chore(frontend): 重命名改为 `wechat`(#69)

## v1.5.0

### chore

- chore(backend): 重命名改为 `wechat`(#67, #68)

## v1.4.3

### fixed

- fix(frontend): 修复登录时认证信息错误的问题(#66)
- fix(backend): 优化认证信息错误解析失败的问题(#66)

### chore

- chore(frontend): 迁移到 biome(#65)

## v1.4.2

### fixed

- fix(frontend): 修复登录时提示未知错误的问题(#64)

## v1.4.1

### optimized

- optimize(frontend): 优化登录提示(#63)

## v1.4.0

### changed

- changed(backend): 认证方式改为 `open_id` + `session_key` 的 hash 值以增强安全性(#62)
- changed(frontend): 优化认证方式(#62)

### optimized

- style(frontend): 重命名 shorturl 为 shortUrl(#60)

## v1.3.1

### optimized

- optimized(backend): 优化 `Config` 实现(#58)

## v1.3.0

### changed

- chore: 从 sqlite 更改为 postgresql(#57)

## v1.2.0

### fixed

- fix(backend): 中文长度计算错误的问题(#54)
- fix(frontend): 修复构建报 warning 的问题(#55)

### changed

- chore(frontend): 由 `weui` 更换为 `tdesign-miniprogram`(#52)

## v1.1.10

### optimized

- optimize(frontend): 优化 totp 定时器更新机制(#46)

## v1.1.9

### fixed

- fix(backend): totp 独立更新周期不生效(#44)

## v1.1.8

### added

- feat(backend): totp 支持独立更新时间(#41)
- feat(frontend): totp 支持独立更新时间(#42)

## v1.1.7

### fixed

- fix(frontend): 锁屏前在 TOTP 页面锁屏后小程序 js 报异常(#35)
- fix(frontend): 二维码扫描出错时微信js报错(#36)

## v1.1.6

### optimized

- optimized(backend): 优化提示信息(#32)

## v1.1.5

### optimized

- optimized(frontend:submit): 优化提交中的 Promise 逻辑(#26)

### added

- feat(backend): 参数验证(#28)
- feat(backend): 支持 tracing(#29)

## v1.1.4

### added

- feat(frontend:core): 增加小程序升级提示功能(#25)

### optimized

- optimized(style): 消除 ts 的 any，增加 eslint 等检查(#23)

## v1.1.3

### fixed

- fixed(frontend:totp): totp 创建后未自动刷新列表(#15)
- fixed(frontend:totp): totp 列表多时，创建按钮会被覆盖(#18)
- chore: 请求报错：unable to get local issuer certificate(#20)

## v1.1.2

### optimized

- optimized(frontend:totp): totp 页面使用 weui-slideview 左滑功能提升性能(#11)
