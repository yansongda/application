# Changelog

本文件遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.5.0] - 2026-11-26

### Added

- 新增底部「TOTP / 我的」自定义 tabBar（`tabBar.custom`，`t-icon` 线性图标 + 品牌绿 `#5bb43b` 高亮，不引入图片资源）；首页顶部「头像 + 已保护 X 个账号」整行下线，头像 / 昵称 / 已保护账号数统一由「我的」tab（原个人中心，导航标题改为「我的」）承接 (#220)

### Changed

- 切 tab / 从子页返回不再每次都弹「加载中」：仅首屏与手动重试保留 loading 反馈；备份页、注销页 loading 统一为 `withLoading` 风格 (#220, #223)
- 页面错误提示合并为单处：创建、编辑发行方 / 用户名、标签编辑、详情页原先「Toast 气泡 + 顶部横幅」弹同一条错误，改为只弹顶部横幅 (#221)
- 倒计时改为全应用单定时器并对齐整秒：每张卡片自建 `setTimeout + setInterval` 与本地递减（N 张卡片 2N 个定时器）收敛为全局 1 个订阅源，消除倒计时漂移 (#225)

### Fixed

- 修复首页搜索按截断后的文本匹配：发行方超 7 字、用户名超 50 字时后半段搜不到（如「Google Cloud Platform」搜「Platform」无结果），改为按完整 issuer / username 匹配，截断只作用于展示 (#224)
- 修复排序结果保存失败提示错误：原先复用「查询列表失败」（2300），新增 2308「排序失败」(#222)
- 修复拖拽排序：进入排序模式瞬间列表跳变（初始顺序改沿用当前展示序、置顶优先）；补齐长按定时器清理与 `bindtouchcancel`，避免打断手势后拖拽卡死；拖动时只更新位移，不再整份数组回写 (#224)
- 修复脏缓存 `period`（0 / 小数 / 非数字）导致算码抛 `INVALID_PERIOD`、进度条按 `remaining / period` 算出 NaN，统一回落 30s (#225)
- 修复注销账号后算码实例缓存（持有明文 secret）残留至进程退出，注销清理链显式清空 (#223)

## [1.4.0] - 2026-11-21

### Changed

- 手动创建改为**用户名必填且不得包含冒号**：`otpauth://` 的 label 必须携带非空 `account`，原先留空会被 OTP 库以「二维码不是有效的 otpauth 链接」拒收（该文案面向扫码场景），现改为提交前拦截并分别提示「请填写用户名」/「用户名不能包含冒号」 (#211)
- 扫码添加收紧：无 label 的 `otpauth://totp/?secret=…`、重复查询参数、非十进制 `digits` / `period` 等畸形 URI 一律拒收，提示「二维码不是有效的 otpauth 链接」 (#211)
- 面向用户的错误文案统一：仅自建错误（`AppError` 子类）的 message 作为产品文案展示，微信接口 `wx.*` errMsg 与第三方库英文错误码不再直接展示，统一回落「操作失败，请重试」；`EE` / `WeixinError` / `HttpError` 改继承 `AppError`，保留 `instanceof Error` 与 stack 语义 (#206)
- OTP 实现迁移到独立 npm 包 `@yansongda/miniprogram-otp@^2.0.0`（与本仓库零依赖自研实现同源，算法 / 码值不变）：删除本地 `src/otp/`（20 文件 / 约 1800 行）与 `tests/otp/`（242 项重复测试），`utils/totp.ts` / `utils/totp-uri.ts` 改为从包入口导入；错误码表按 `OtpErrorCode` 穷尽，库新增码时编译期报错 (#205, #211)
- `check:otp-invariants` 替换为 `check:otp-dependency`：校验依赖版本基线、`dist/index.js` 指纹、RFC 4226 / 6238 向量与关键错误码冒烟，并禁止业务代码深 import 已删除的 `src/otp` (#205)
- 升级 `@biomejs/biome` `^2.5.1` → `^2.6.8`、`tdesign-miniprogram` `^1.15.2` → `^1.18.0`：biome 2.6 纳入 `src/**/*.scss` 检查（`pages/totp/index.scss` 调整 `.menu-label` 声明顺序消除 `noDescendingSpecificity` 警告，级联行为不变）；tdesign 1.17 起组件间距 / 圆角 / 字号全量 token 化、1.18 起 Toast / Message / Popup / Overlay 等 `z-index` 改由样式表变量提供（默认值与旧硬编码一致，本项目仅覆盖品牌色）；Radio / Checkbox 圆形图标描边统一 2px、Textarea placeholder 字号修正属视觉微调 (#212)

## [1.3.1] - 2026-11-11

### Fixed

- 修复首页列表卡片左右留 16px 边距、分组表头内边距过大：改为通栏卡片（圆角 10px + `overflow: hidden` 裁切滑出按钮）、分组表头 4px 内边距，与华为 MFA 元服务对齐，平铺 / 分组 / 排序三种视图宽度统一 (#203)

## [1.3.0] - 2026-11-11

### Added

- 新增「导入 / 导出」加密备份页（`pages/backup`）：导出为口令加密的 `.mfa` 备份（保存并发送文件 / 复制到剪贴板），支持从聊天文件或剪贴板导入，自动识别内容而不看后缀；加解密全部由服务端完成（`POST /api/v1/backup/export|import`，`kind=totp`，15s 超时），前端仅做无口令结构预检 (#198)
- 首页空态新增「从其它应用导入」入口，个人中心「更多」新增「导入 / 导出」入口 (#198)
- 使用帮助新增「加密备份」说明：口令不保存不可找回、单次最多 50 条、重复导入会新增重复条目、剪贴板与聊天记录需及时清理 (#198)
- 备份契约常量与模型层（信封标识 / 版本 / 条数上限 / 长度上限 / 剪贴板安全上限）、接口封装与后端错误码（2023~2028 / 9903 / 9908）文案映射 (#198)
- 新增 `utils/datetime.ts`、剪贴板读取 `readText` 与 `.mfa` 文件通道工具，并补充备份信封 / 口令策略 / 编排 / 时间格式化单测 (#198)

### Fixed

- 修复 Android 真机微信 SOTER 指纹 / 面容认证期间触发 `onHide` 导致进行中的验证被误作废、开关页误报「操作过于频繁」 (#201)
- 修复应用锁时序误判：页面 `onShow` 早于 App `onShow` 时按退后台时间戳补判；未达 60s 清时间戳、开启应用锁后清 `lastHideAt`，避免后续切页误锁 (#201)
- 新增验证悬挂保险（30s 无回调强制复位），避免 SOTER 控件异常导致解锁永久 `SKIPPED` 锁死 (#201)
- 修复删除小程序重装后首屏漏锁：新装 / 重装先恢复安全设置再渲染验证码，个人中心渲染前同样复核并上锁 (#201)
- 修复开发版（IDE / 真机调试）取不到上传版本号时个人中心显示 `v0.0.0`，改为只展示环境标签 (#198)

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
