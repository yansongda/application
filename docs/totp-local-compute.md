# TOTP 验证码前端本地计算改造方案（TOTP 微信小程序）

> **时间**：2026-09-05
> **作者**：GLM 5.3 Flash + yansongda
> **状态**：经过人工审核确认

## 1. 背景与问题

**现状**：TOTP secret 存于后端 `tool.totp` 表 `config` JSON 列（`{"secret": "<base32>", "period": N}`，明文）。TOTP 小程序展示验证码时，列表页的验证码由 `components/totp/item.ts` 组件负责取码：按本地时钟对齐周期末（`remainSeconds = period - (now.getSeconds() % period)`），周期末调 `POST /totp/detail` 由后端 `totp-rs` 实时计算 code 返回；详情页为纯信息展示页，不展示验证码、不使用该组件（已验证：`detail/index.wxml` 无 `app-totp-item`，`detail/index.json` 未注册）。secret 仅在扫码添加时随 `otpauth://` URI 发给后端入库（`Totp::from_url_unchecked` 解析，仅落库 step/secret/issuer/account_name），从不回传前端。主小程序 yansongda 有一套相同的 TOTP 页面，同样依赖后端算码。

**困境**：

1. 每个周期（通常 30s）一次网络往返 + 一次 DB 查询，仅为取一个本可本地计算的码——TOTP 设计初衷就是离线可用
2. 断网/弱网/后端不可用时，验证码完全不可用，验证器工具退化为"联网才有用"
3. 每次刷码的服务端算力与流量开销纯属浪费（验证码数量随用户账户数线性增长）
4. 时机上现在改造成本最低：后端契约已稳定，前端只有 4 个页面 + 1 个组件

**目标**（约束条件）：

- **TOTP 小程序验证码本地离线计算**，展示环节零网络依赖
- **主小程序零改动**（`/all` 响应新增字段向后兼容，主小程序继续走后端算码）
- **secret 仍以服务端为唯一可信源**（账号体系、换机恢复能力不变——secret 本就明文存后端，云备份是现状能力，不能丢）
- **后端变更最小化**（`/all` 响应结构增加 secret 字段，无新增接口）

## 2. 整体方案

**核心思路**：复用带鉴权的 `/all` 接口并在响应中携带 secret（`DetailResponseConfig` 增加 `secret` 字段），小程序登录同步后把 secret 缓存到设备本地，验证码改由本地 `otpauth` 库计算；账户的增删改排序仍走后端（不变），成功后同步更新本地缓存。

**架构与数据流**：

```
【改造前：TOTP 小程序】
扫码 URI ──POST /totp/create──▶ MySQL(tool.totp: secret+period)
每周期末 ──POST /totp/detail──▶ 后端 totp-rs 算 code ──▶ 倒计时展示

【改造后：TOTP 小程序】
同步期(启动/变更后):  POST /totp/all(响应携带 secret) ──▶ 本地缓存(storage)
展示期:             本地 otpauth 算 code ──▶ 倒计时展示   ← 零网络
变更期:             create/edit/delete/sort ──▶ 后端(不变) ──▶ 成功后更新本地缓存

【主小程序 yansongda】代码不变，继续后端算码（/all 响应新增 config.secret 字段向后兼容，其余接口原样保留）
```

**文件结构**（变更后）：

```
application-rs/
├── application-api/src/routes.rs             [不动] /all 原路由复用，无新增注册
├── application-api/src/request/totp.rs       [改] DetailResponseConfig 增加 secret 字段
├── application-api/src/service/totp.rs       [不动] all() 复用
├── application-api/src/v1/totp.rs            [不动] all() handler 复用
└── application-database/src/tool/totp.rs     [不动] fetch/all 已可取回 config，复用

wechat/miniprogram/totp/
├── package.json / bun.lock                   [改] 引入 otpauth ^9.5.2（类型与锁文件）
├── src/vendor/otpauth.esm.min.js (+.esm.min.d.ts) [新] 自包含 ESM 运行时（规避包 main 入口 node:crypto）
├── biome.json                                [改] files.includes 排除 src/vendor
├── src/constant/totp.ts                      [不动] 无新增 PATH
├── src/constant/app.ts                       [改] STORAGE.TOTP_CACHE
├── src/constant/error.ts                     [不动] 无新增错误码
├── src/types/totp.d.ts                       [改] ItemConfig 增加 secret；CacheItem / TotpCache 类型
├── src/api/totp.ts                           [改] create() 返回类型 null → Item；detail() 保留不再被 item 调用
├── src/utils/http.ts                         [改] 增量新增 postWithHeader()（读 Date 头），现有行为零变化
├── src/utils/totp.ts                         [新] otpauth 封装：URI 解析 + 本地算码（强制 SHA1+6位）
├── src/utils/totp-cache.ts                   [新] 本地缓存读写/同步/时间偏移
├── src/components/totp/item.ts               [改] 本地算码替代 api.detail 周期末取码（仅列表页使用）
├── src/pages/totp/index.ts / index.wxml      [改] 缓存渲染 + create/delete/sort 更新缓存；组件绑定调整
└── src/pages/totp/detail/index.ts            [改] 缓存读取（信息展示页，无验证码）；edit/{issuer,username}.ts 更新缓存
```

## 3. 详细设计

### 3.1 后端：/all 响应携带 secret

与现有接口同挂 `authorization` hoop（Bearer token → 查 `account.access_token` 表校验，opaque ULID——已验证，`middleware.rs:42 起`）。`/all` 响应中的 `config` 结构（`DetailResponseConfig`）增加 `secret` 字段，`/detail` 响应同构同步携带：

```json
{
  "code": 0,
  "message": "success",
  "request_id": "01J...",
  "data": [
    { "id": "1", "issuer": "GitHub", "username": "a@b.c", "config": { "secret": "JBSWY3DPEHPK3PXP", "period": 30 }, "code": "123456" }
  ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `config.secret` | string | base32 secret（`TotpConfig.secret` 原值） |
| `config.period` | number | 周期秒数（`TotpConfig.period`） |

后端净变更仅为 `DetailResponseConfig` 增加一个字段，无新增接口（原独立 secret 下发接口方案已废弃，见修订记录）。

**日志决策（B2，已确认）**：现有 `request_logger` 会记录请求 headers/body 与响应体（`middleware.rs` `read_body_for_log`——已验证）。`/all` 响应中的 secret 将进入后端日志。经评估接受该现状：`create` 请求体本就记录完整 `otpauth://` URI（含 secret），日志出现 secret 非新暴露类别，本次**不改 middleware**。`truncate_for_log` 截断可能产生半截 secret，属于既有日志机制的已知局限。

### 3.2 前端：本地缓存与同步

storage key `TOTP_CACHE`（值 `totp_cache`，与现有 `TOKEN_BUNDLE` 并列，`constant/app.ts`），结构：

```json
{
  "synced_at": 1757059200,
  "clock_offset": 0,
  "items": [
    { "id": "1", "issuer": "GitHub", "username": "a@b.c", "secret": "JBSW...", "period": 30 }
  ]
}
```

同步策略（`utils/totp-cache.ts`）：

| 时机 | 动作 |
|------|------|
| 列表页 onShow 且登录态就绪（复用 `ensureAuthenticated`，`utils/app.ts` 单飞已验证） | 全量同步：单接口 `/all`（响应携带 secret）→ **整体覆写**缓存；顺序沿用 `/all` 返回序（后端 `order by sort desc, id asc`——已验证） |
| create 成功 | 用 `DetailResponse.id` + 本地解析的 secret/period 乐观写入缓存（issuer 取本地解析值，空则"未知发行方"） → 后台再全量同步校正（对冲本地解析与后端入库的差异） |
| edit issuer/username 成功 | 直接更新缓存对应字段 |
| delete 成功 | 直接移除缓存条目 |
| sort 成功 | 本地按新顺序重排缓存 |
| 同步失败但有缓存 | **用缓存离线展示**（严格优于现状的空列表报错） |
| 同步失败且无缓存（首次使用即断网） | 列表空 + 错误提示（与现状一致） |

`clock_offset`：同步时读响应 `Date` header（经 `http.ts` 增量新增的 `postWithHeader()`，用于 `/all`），`offset = server_time - local_time`；header 缺失（wx.request 各平台 header 键大小写不一，需**大小写不敏感**查找）或 `|offset| > 60s`（异常时钟保护，防错码）则置 0 并 logger.warning（Task 0 验证 header 可用性——推断，未实测）。

**缓存构建规则**：直接以 `/all` 响应构建缓存条目（id/issuer/username/secret/period），无合并环节。已知竞态：create 的乐观写入可能被一个在途的旧全量同步覆写（旧响应后到）——影响仅为短暂数据缺失，下次 onShow 同步自愈，接受该行为。

### 3.3 前端：本地 TOTP 计算（关键决策：参数对齐）

后端 `generate_code()`（已验证，`tool/totp.rs:39-59`）为 `build_noncompliant` + **强制 SHA1 + 强制 6 位 + skew=1**，period 取每条 config；create 时（`service/totp.rs`，已验证）`Totp::from_url_unchecked` 解析后**只落库 step/secret/issuer/account_name**，URI 中的 algorithm/digits 参数即被丢弃。前端必须复刻同样行为，否则存量非标准账户（如 URI 声明 SHA256/8 位的）本地算出的码会与后端历史行为不一致。

| 参数 | 后端 totp-rs（已验证） | 前端 otpauth 封装 | 理由 |
|------|------|------|------|
| 算法 | 强制 SHA1 | 强制 SHA-1，忽略 URI 参数 | 与后端一致，存量账户码不变 |
| 位数 | 强制 6 | 强制 6，忽略 URI 参数 | 同上 |
| 周期 | `config.period`（URI step） | `/all` 下发的 period | |
| skew | 1（用于校验容忍；算码取当前步） | 取当前步 | `generate_current()` 返回单码，行为一致 |
| issuer 展示 | None → "未知发行方" | 沿用后端下发的 issuer 字段 | 不在前端重复解析 |

伪代码（`utils/totp.ts`）：

```
compute_code(item, now = Date.now() + clock_offset):
    totp = new TOTP({ secret: base32(item.secret), algorithm: "SHA1",
                      digits: 6, period: item.period })
    return totp.generate({ timestamp: now })
```

取码路径变化：现状 `components/totp/item.ts` 是列表页**唯一的取码路径**（组件持有 `itemId`，周期末调 `api.detail`——已验证；详情页不展示验证码，见 3.4）。改造后组件新增 `secret` property（由列表页从缓存传入），周期末本地重算，倒计时对齐逻辑（`remainSeconds = period - (now.getSeconds() % period)`）不变。失败兜底：secret 缺失/算码异常 → code 显示 `------` + 现有 `message` 事件提示。

### 3.4 关键流程变化

**创建**：扫码 → **本地解析 URI**（`utils/totp.ts`，基于 otpauth `URI.parse` 解析，暂存 secret/period）→ `api.create(uri)` 原样发后端（**契约零改动**）→ 成功后取返回的 id 乐观写缓存 → 背景全量同步校正。本地解析仅用于乐观展示，服务端 `/all` 数据为最终校正源。

**详情页**：现状为纯信息展示页（issuer/username/period，无验证码、不使用 item 组件——已验证 `detail/index.wxml`）。改造后仅把数据源从 `api.detail` 换成缓存读取（miss 则触发一次同步再读；仍 miss 走现有错误 dialog），并**同步维护 `this.response`**（`gotoEdit` 依赖它向编辑页传参，`detail/index.ts` 已验证）。不涉及本地算码。

**编辑**：edit issuer/username 页保存成功后直接更新缓存字段（返回列表页从缓存渲染，离线也一致）。

**删除/排序**：API 成功后 removeItem / applySort，随后列表页从缓存渲染。

### 3.5 兼容性与库选型

| 项 | 说明 |
|------|------|
| 主小程序 | `/all` 响应新增 `config.secret` 字段向后兼容（未知字段被忽略），主小程序代码零改动 |
| 旧版小程序共存 | `/all` 响应新增字段向后兼容，旧版不使用 secret 字段、不受影响 |
| 包体积 | otpauth 自包含 ESM `dist/otpauth.esm.min.js` 27.6KB（实测，noble-hashes 已内联、0 处 node:crypto），主包 2MB 限制内 |
| 引入方式 | **主路径 vendor**：`dist/otpauth.esm.min.js` 复制入 `src/vendor/`（+ 基名匹配的 `otpauth.esm.min.d.ts` 供 typecheck——tsconfig `allowJs: true`，旁车必须与 import 基名一致；并在 `biome.json` 排除 `src/vendor`）。原因（2026-09-05 实测）：包 `main` 指向 `dist/otpauth.node.cjs` 且顶层 `require('node:crypto')`，微信 packNpm 按 main 解析必然运行时失败；esm/umd 构建自包含无该依赖。package.json 仍声明 otpauth 依赖（bun.lock 锁定；typecheck 类型由 sidecar 提供），不经构建 npm 加载 |
| Bun 工具链 | 项目为 package.json + bun.lock（无 deno.json）；`bun install` 更新锁文件与 node_modules |

**库选型**（对比调研结论，来源官方 npm/GitHub 与社区实践）：

| 方案 | 体积 | 评估 |
|------|------|------|
| **otpauth v9 完整版（已选定）** | 27.6KB | 纯 JS（HMAC 为内联 noble-hashes，非 jsSHA）、ESM/UMD 构建自包含无 Node 依赖、TS 类型、活跃维护（v9.5.2，作者 hectorm） |
| otpauth bare + 自研注入 HMAC | 9.7KB + 代码 | 体积最省，多一层自维护代码 |
| jsSHA 自研 RFC 6238（降级备选） | 8.8KB | ~50 行，依赖面最小，无现成 URI 解析 |

小程序运行时无 WebCrypto/SubtleCrypto（官方文档确认），纯 JS HMAC 是唯一路径。引入方式已定为 vendor 自包含 ESM（见上表，main 入口不适用为实测结论）；Task 0 做包实物核验、Task 2 在 devtools 中做加载冒烟，极端失败再降级 jsSHA 自研。

### 3.6 安全设计

**决策 A（已确认）**：本地存储不做应用层加密，`totp_cache` 与 `token_bundle` 均维持明文——与业界验证器（Google Authenticator / Microsoft Authenticator 应用私有目录存储）处于同一防护档位。

**决策理由**：

1. wx storage 按小程序沙箱隔离（官方机制），已挡住跨小程序读取；文件层有 OS 全盘加密 + 微信沙箱提供基线保护
2. 应用层加密仅改善"备份/root 纯读文件"一档，且离线解密要求密钥同存设备，属弱混淆级保护
3. 只加密 secret 而 `token_bundle`（access/refresh token）明文是伪安全——refresh_token 可直接走 API 重拉全部 secret；真做必须两者一起加密，成本 +0.5~1d，收益与成本不匹配
4. 验证器工具本职是运行时亮码，"解锁手机被直接查看"场景加密无法防御

**决策 B2（已确认）**：`/all` 响应体含 secret 会进后端日志，接受现状不改 middleware（见 3.1）。

**后续增强路径**（本次不做，记录在案）：设备密钥 AES 加密（须连 `token_bundle` 一起）、`/all` 接口限流、审计日志。

## 4. 推进策略

```
Phase 0 契约 spike（约 0.5d，只读 + 临时脚本）
├─ JS 侧 RFC 6238/RFC 4226 向量验证 otpauth 算码（本地可跑）
├─ 测试环境对照：同周期窗口内 /detail 返回码 vs 本地算码（0*，无环境推迟到 trial）
├─ curl -i 验证 Date 响应头（0*）
├─ otpauth 包实物核验（tarball 解包：main 字段 + esm.min 无 node:crypto；本地可跑）
└─ 验证点：向量断言 PASS + 契约快照文档落盘
Phase 1 后端（约 0.5d，变更最小化）
├─ /all 响应携带 secret（DetailResponseConfig +secret）；cargo check/clippy/fmt 全绿
└─ 验证点：测试环境 curl 返回正确 JSON（0*）；主小程序 /all 回归正常
Phase 2 TOTP 小程序（约 1-1.5d）
├─ 基础层：依赖 + 类型 + 常量 + api + utils(totp/totp-cache/http 增量)
├─ 组件与页面：item 本地算码 + 页面缓存渲染 + 变更后更新缓存
├─ devtools 加载 vendor ESM 冒烟（0*，需用户 devtools）
├─ bun run biome:check + typecheck 绿
└─ 验证点：trial 版与现网 release 版同账户同码；飞行模式算码可用；增删改排序回归
Phase 3 发布
├─ 后端先发（变更最小化、可独立回滚）；小程序后发
└─ 回滚：小程序微信后台「版本回退」即回到后端算码；后端 /all 响应多出的字段对旧版无影响
```

## 5. 风险与对策

| 风险 | 严重度 | 对策 |
|------|--------|------|
| otpauth JS 与 totp-rs 算码不一致（短 secret、URI 参数差异等边界） | 高 | Task 0 向量 + 环境对照验证为准；不一致则调参，仍不一致换 jsSHA 自研逐位对齐 |
| vendor ESM 在小程序运行时加载异常（极端） | 中 | 包实物核验在 Task 0、devtools 加载冒烟在 Task 2（esm 自包含、0 处 node:crypto 已实测）；极端失败降级 jsSHA 自研 |
| secret 暴露面扩大（/all 下发 + 本地明文 + 响应体日志） | 中 | 已决策接受（A + B2）：与业界一致、风险记录在案；服务端为可信源可随时重置；后续增强路径见 3.6 |
| 设备时钟漂移导致错码 | 中 | `Date` header 偏移校准（不可用降级 offset=0）；主小程序后端算码不受影响 |
| 本地缓存与后端不一致（同步间隙变更） | 低 | 全量覆写为最终态；变更操作本地即时更新 |
| /all 仍为每条算 code 的浪费（历史问题） | 低 | 本次不动（主小程序共用）；记录为后续优化项 |

## 6. 监控与可观测性

小程序无上报通道（现状如此，本次不新建）：维持 console 日志 + 微信后台 JS 错误看板。后端沿用现有请求日志（/all 响应体含 secret 入日志为 B2 已接受行为）；观察方式为用户反馈 + 后端日志抽查同步接口调用量。告警：无（无基础设施，不虚构指标）。

## 附录 A：契约快照（2026-09-05，验证状态标注）

**已验证（读过源码）**：

```
POST /api/v1/totp/all   Authorization: Bearer <token>
→ {"code":0,"message":"success","request_id?":"...","data":[
     {"id":"1","issuer":"GitHub","username":"a@b.c","config":{"secret":"JBSW...","period":30},"code":"123456"}]}
   // DetailResponse（request/totp.rs:22-35，DetailResponseConfig 含 secret+period）；issuer 为 None 时返回"未知发行方"
   // 排序 order by sort desc, id asc（tool/totp.rs:78）

POST /api/v1/totp/create   {"uri": "otpauth://totp/..."}
→ data 同 DetailResponse（含新建 id）
   // service/totp.rs create(): Totp::from_url_unchecked → 仅落库 step/secret(base32)/issuer/account_name
   // URI 中 algorithm/digits 参数被丢弃

generate_code（tool/totp.rs:39-59）: SHA1 + 6位 + skew=1 + build_noncompliant，period=config.period
TotpConfig（tool/totp.rs:63-66）: {"secret": String, "period": u64}
鉴权（middleware.rs:42 起）: Bearer token → account.access_token 查表校验（opaque ULID，非 UUID v7）
日志（middleware.rs:76 起 request_logger、147 起 read_body_for_log）: 记录请求 headers+body、响应体（JSON），B2 已接受
前端取码路径（components/totp/item.ts）: 组件仅列表页使用（wxml 标签 app-totp-item，普通列表与 dragItems 两处绑定均传 code），周期末 api.detail
详情页（pages/totp/detail/）: 纯信息展示，wxml 无 app-totp-item、index.json 未注册该组件；detail/index.ts 维护 this.response 供 gotoEdit 传参
edit 页面结构: 平铺文件 src/pages/totp/edit/{issuer,username}.ts（非 index/ 子目录，app.json 证实）
构建配置（project.config.json）: packNpmManually=true, packNpmRelationList → ./src（miniprogram_npm 在 src/ 下；本方案不依赖构建 npm 加载 otpauth）
工具链: package.json + bun.lock，无 deno.json；biome.json files.includes: [src/**/*, !src/miniprogram_npm/**/*]（vendor 产物需显式排除）；tsconfig allowJs: true（sidecar d.ts 命名须与 import 基名一致）
otpauth 9.5.2 包实测（2026-09-05 npm 实装）: main=./dist/otpauth.node.cjs（顶层 require('node:crypto')）；exports deno/default → dist/otpauth.esm.js；esm/umd 构建自包含（内联 noble-hashes 2.4.0，0 处 node:crypto）；d.ts 导出 {HOTP, Secret, TOTP, URI, version}，URI 解析 API 为 URI.parse(uri): HOTP|TOTP（无 TOTP.fromURI）
```

**推断（未实测，Task 0 确认）**：

```
otpauth JS 与 totp-rs 对短 secret / 非标准 URI 的算码一致性（Task 0 向量 + 环境对照）
vendor ESM 在微信 devtools/真机的加载与运行（Task 0 冒烟；wx.request 响应 header 键大小写各平台不一，已按大小写不敏感处理）
/api/v1/totp/* 响应的 Date 头可用性（Task 0 curl -i）
otpauth URI.parse 对极短 secret 的接受范围
```

## 附录 B：调研依据

- otpauth v9.5.2（作者 hectorm）：https://github.com/hectorm/otpauth / https://www.npmjs.com/package/otpauth（注：HMAC 实现为内联 noble-hashes；URI 解析 API 为 `OTPAuth.URI.parse`）
- RFC 6238 测试向量：https://datatracker.ietf.org/doc/html/rfc6238#appendix-B；RFC 4226 Appendix D（6 位）：https://datatracker.ietf.org/doc/html/rfc4226#appendix-D
- 小程序无 SubtleCrypto / wx.getRandomValues 存在：https://developers.weixin.qq.com/miniprogram/dev/api/device/crypto/wx.getRandomValues.html
- UserCryptoManager 用户密钥依赖登录链路（未采用）：https://developers.weixin.qq.com/miniprogram/dev/framework/open-ability/user-encryptkey.html
- 库体积实测：jsdelivr 文件清单（otpauth 完整 ESM 27.6KB min；jsSHA sha1.mjs 8.8KB）

## 修订记录

- 2026-09-05：PR #162 review 后修订（方案 A）——/all 响应携带 secret（DetailResponseConfig +secret），移除 /secrets 接口；前端同步改单接口。
- 2026-09-05：设计文档随方案 A 更新后正式入库；同分支已将包管理器从 Deno 迁移至 Bun，文中工具链表述同步更新。
