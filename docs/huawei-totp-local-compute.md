# 华为元服务 TOTP 验证码端内计算改造方案（MFA 元服务）

> **时间**：2026-09-30
> **作者**：DeepSeek V4.1 Flash + yansongda
> **状态**：经过人工审核确认

## 1. 背景与问题

**现状**（均已读源码验证）：

- 华为元服务首页每条目在 `onAttach`（`huawei/atomicservice/MFA/entry/src/main/ets/pages/index/Index.ets:275-278`）、**每个周期到点**（`models/Runtime.ets:147-169` 的 `schedule()` → `:169` timeout → `start()`）、回前台（`ability/EntryAbility.ets` `onForeground` → `resumeAll`）都会调 `POST /api/v1/totp/detail` 取后端算好的验证码；详情页同理（`pages/index/Detail.ets` 的 `onActive → runtime.start()`）。
- 后端响应已携带 `config.secret`（`application-rs/application-api/src/request/totp.rs:22-27,54-58`；值来自 `application-rs/application-api/src/service/totp.rs` `create()` 的 `totp.secret().to_base32()`），但华为前端 `IItemConfig` 只声明了 `period`（`types/Item.ets:9-11`），secret 从未被消费。
- 微信「TOTP安全码」小程序已完成同一改造（`docs/totp-local-compute.md`，PR #162）：本地算码 + 本地缓存，周期翻转零网络。

**困境**：

1. 每个账户每周期一次 HTTP + 一次 DB 查询，只为取一个本地即可算出的码；首屏 N 个条目会并发 N 次 `detail` 请求，且每周期再来一轮。
2. 断网/弱网下验证码完全不可用——验证器的本职能力（离线亮码）在华为端彻底缺失（当前无任何本地缓存）。
3. 同一后端、同一 secret，两端行为不一致（微信已本地化，华为仍联网取码）。
4. 潜在对齐缺陷（本地算码后会立刻暴露）：进度条用 `new Date().getSeconds() % period` 对齐（`Runtime.ets:156`），当 period 不是 60 的约数（如 45s）或时区偏移非整小时（如 +05:30）时，「倒计时归零」与「验证码翻转」不同刻。

**目标**（约束条件）：

- **零后端改动**（复用已下发的 secret）
- **展示期零网络**（周期翻转、回前台、进详情页不发请求）
- **算码与后端逐位一致**（存量账户同一时间窗码不变）
- **与微信端语义对齐**（强制 SHA1/6 位，忽略 URI 中的 algorithm/digits）
- **不新增三方依赖**
- **异常账户可降级**，**secret 不落盘、不进日志**
- **可回退**（保留现有 detail 取码路径作兜底）

## 2. 整体方案

**核心思路**：**用系统 CryptoArchitectureKit（cryptoFramework）在端内实现 RFC 6238 算码（HMAC-SHA1 + 6 位 + period），secret 取自 `/totp/all` 已下发的明文 base32；把「取码」从网络调用换成端内计算，计算异常时回落到现有 `/totp/detail`。**

```
【改造前】
列表 attach / 周期到点 / 回前台 / 进详情 ──POST /totp/detail──▶ 后端 totp-rs 算码 ──▶ 展示 + 端内倒计时

【改造后】
同步期（仅页面刷新/变更后）: POST /totp/all（响应已含 config.secret，契约零改动）──▶ 内存态 ItemsRuntime
展示期: 端内 cryptoFramework HMAC-SHA1 算码 ──▶ 展示 + 端内倒计时        ← 零网络
兜底（仅异常 secret，罕见）: 端内计算失败 ──POST /totp/detail──▶ 后端码
```

**实现选型对比**：

| 方案 | 评估 |
|------|------|
| **系统 cryptoFramework HMAC-SHA1（选定）** | 零依赖、元服务 API 12+ 原生可用、无需权限；只需自写 base32 解码 + 动态截断（约 60 行） |
| 搬微信同款 otpauth ESM（纯 JS 27.6KB） | 微信用它是因为小程序运行时无 WebCrypto；体积压缩产物需过 ArkTS 静态检查，风险高，仅省 60 行代码 → 不采纳 |
| ohpm `@ohos/crypto-js` | 新增三方依赖，且同样命中弱算法 lint 规则 → 不采纳 |
| 手写纯 ArkTS SHA1/HMAC | 自维护密码学实现、实质是绕过 lint 意图 → 不采纳 |

**文件结构**（变更后）：

```
huawei/atomicservice/MFA/
├── entry/src/main/ets/
│   ├── types/Item.ets                 [改] IItemConfig 增加 secret?: string
│   ├── models/Runtime.ets             [改] freshCode 端内算码+兜底；新增 rotate；周期到点本地翻转；resume 立即重算；reload 不覆盖本地码；倒计时 epoch 对齐
│   ├── utils/TotpMath.ets             [新] base32 解码 + 8 字节大端计数器 + 动态截断（纯函数，无系统 kit 导入）
│   ├── utils/TotpCode.ets             [新] HMAC-SHA1 算码（cryptoFramework，导出 TotpCode.compute）
│   ├── api/Totp.ets                   [不动] detail 保留作兜底
│   ├── pages/index/Index.ets          [不动] refresh/reload/start/stop 全部复用
│   ├── pages/index/Detail.ets         [不动]
│   ├── pages/index/create/Index.ets   [不动] 仍上送 otpauth URI
│   └── utils/Http.ets                 [不动]
└── entry/src/test/
    ├── TotpCode.test.ets              [新] base32/计数器/截断单测（hypium）
    └── List.test.ets                  [改] 注册新测试套
```

后端（`application-rs/**`）、微信端（`wechat/**`）、华为页面与 API 层：**零改动**。

## 3. 详细设计

### 3.1 契约（标注验证状态）

```
POST /api/v1/totp/all      Authorization: Bearer <access_token>
→ {"code":0,"message":"success","data":[
    {"id":"1","issuer":"GitHub","username":"a@b.c",
     "config":{"secret":"JBSWY3DPEHPK3PXP","period":30},"code":"123456"}]}
```

| 项 | 结论 | 状态 |
|----|------|------|
| `config.secret` 已下发 | `DetailResponseConfig{secret, period}`，`/all`、`/detail`、`/create` 三接口都返回明文 base32 | 已验证（`request/totp.rs:22-27,54-58`；`service/totp.rs`） |
| secret 形态 | 大写、**无填充** base32（totp-rs 6.0.0 `Secret::to_base32()` → base32 0.5.1 的 RFC4648 无填充编码） | 已验证（读过 `~/.cargo/registry` 中 totp-rs/base32 源码） |
| 后端算码参数 | SHA1 + 6 位 + skew 1 + step=config.period（`build_noncompliant`） | 已验证（`application-database/src/tool/totp.rs:39-58`） |
| period 来源 | 后端下发；用户创建时手填（`pages/index/create/Index.ets:114-117` 校验、`:124-125` 构造 URI）；无 digits/algorithm 字段 | 已验证 |
| 「secret 只下发一次」 | 否，每次列表/详情都返回 | 已验证 |
| 兜底 `/totp/detail` | 请求 `{id}`，响应同构（含 code） | 已验证（`api/Totp.ets:68-83`） |
| cryptoFramework 能力 | 官方算法规格表：HMAC 摘要算法含 **SHA1（API 9+）**；HMAC 密钥「可以是任何长度」，字符串参数 `HMAC` 支持 **[1, 32768] 位（1~4096 字节）**，短密钥末尾补 0；`init/update/doFinal`（init+doFinal 必选、update 可选）；原子化服务 API 12+ 可用、无需权限。注意**不得使用 `HMAC\|SHA1` 规格**（要求密钥恰为 160 位） | 已验证：官方文档原文（2026-09-30 审查期复核，见附录 B） |

### 3.2 算法设计

| 参数 | 后端 | 端内 | 说明 |
|------|------|------|------|
| 算法 | 强制 SHA1 | 强制 SHA1 | URI 里的 algorithm 后端已丢弃，端内同样忽略 |
| 位数 | 强制 6 | 强制 6 | 同上忽略 digits |
| 周期 | `config.period` | `/all` 下发的 `config.period` | 缺失兜底 `DEFAULT_PERIOD`（30） |
| 计数器 | `floor(epoch / period)` | 同 | 8 字节大端 |
| skew | 1（仅校验容忍） | 不参与算码 | `generate_current()` 只取当前步 |

```
compute(secret, period, nowMs):
    key  = base32Decode(secret)          # 大写/去空白/去尾部 '='；空或非法 → throw
    ctr  = floor(nowMs / 1000 / period)  # JS 安全整数（T=20000000000 也必须正确）
    msg  = uint64_be(ctr)                # high/low 各 4 字节
    mac  = HMAC_SHA1(key, msg)           # cryptoFramework
    off  = mac[len-1] & 0x0f
    v    = ((mac[off] & 0x7f) << 24) | (mac[off+1] << 16) | (mac[off+2] << 8) | mac[off+3]
    return zeroPad6(v % 1000000)
```

关键特性：纯函数（同输入必同输出）；只依赖 epoch，不依赖设备时区；密钥长度自适应（与后端 hmac 行为一致）。

### 3.3 端内实现要点（`utils/TotpMath.ets` + `utils/TotpCode.ets`）

纯计算（base32 解码 / 计数器打包 / 动态截断 / 零填充）与系统 kit 调用分离为两个文件：`TotpMath.ets` 不 import 任何 `@kit.*`，因此可被 `entry/src/test` 的本地单测加载；`TotpCode.ets` 只负责 HMAC 调用与对外 `compute()`。

- 导入 `import { cryptoFramework } from '@kit.CryptoArchitectureKit';`
- HMAC 调用链：`createSymKeyGenerator('HMAC')` → `convertKey({data: key})` → `createMac('SHA1')` → `init(symKey)` → `update({data: msg})` → `doFinal()`
- **密钥规格**：必须用通用 `HMAC` 规格（官方：密钥「可以是任何长度」、[1, 32768] 位、短密钥末尾补 0）；**不得用 `HMAC|SHA1`**（该规格要求密钥恰为 160 位，短 secret 会直接失败）
- **Base32 解码**：`A-Z2-7` 字母表，忽略空白与尾部 `=`，按 8 字符→5 字节分组、末组按剩余有效位截断（与 base32 0.5.1 的 decode 规则一致）；结果为空或含非法字符 → 抛错（触发兜底）
- **计数器**：`high = Math.floor(ctr / 4294967296)`、`low = ctr % 4294967296`，用 `>>>` 写 8 字节，避免 32 位溢出
- **竞态控制**：以调用时刻 timestamp 计算 + 实例内单调序号，`await` 返回后仅最新序号可写入 `code`，防止旧结果覆盖新码
- **失败语义**：内部不吞错、不打日志，异常抛给 Runtime 决定兜底/提示

### 3.4 运行时集成（`models/Runtime.ets`）

| 时机 | 现状 | 改造后 |
|------|------|--------|
| 列表条目 attach | `start()` → detail 请求 | `freshCode()` 端内算码 + 排程（零请求） |
| 周期到点 | timeout → `start()` → detail 请求 | timeout → `rotate()`：端内重算 + 重排程（零请求） |
| 回前台 `resume()` | 仅 code 缺失时 detail 请求 | **总是**端内重算（设备时间可能已跨窗）+ 重排程 |
| 页面刷新 `reload()` | 写服务端 code + `resume()` | 端内码为权威来源：仅在该条目尚无 code 时用服务端值兜底，随后 `resume()` 端内重算 |
| 详情页 `onActive` | `start()` → detail 请求 | 端内算码（零请求） |
| 兜底 | — | `freshCode()` 内：端内失败 → `Totp.detail(id)`（网络，保留现有 Toast 失败提示） |

**倒计时对齐修正**（必要项，与微信端一致）：`progress = period - (Math.floor(Date.now()/1000) % period)`，替换 `Runtime.ets:156` 的 `getSeconds() % period`。

### 3.5 失败与降级

| 场景 | 行为 | 用户可见 |
|------|------|----------|
| secret 缺失或为空串（扫码入库的异常账户：如 `secret=A` 经 base32 解码为 0 字节、再编码入库即为空串；含非法字符的输入在 `create` 阶段已被后端拒绝） | 回落 `/totp/detail` | 正常显示后端码 |
| cryptoFramework 调用异常（含空密钥非法参数、SHA1 规格不可用） | 回落 `/totp/detail` | 正常显示后端码 |
| 端内与后端同时失败（离线） | 保留最后一次 code，无则空串 | 与现状一致（Toast 提示） |
| `config.period = 0`（扫码可注入） | **端内不可达**：后端 `generate_code()` 在 totp-rs `sign()` 的 `time / step` 处 panic（`~/.cargo/.../totp-rs-6.0.0/src/lib.rs:239`；`build_noncompliant`、`with_step_duration` 均不校验 step，`url.rs:116-121` 仅做 `u64` 解析），`/all`、`/detail` 整体失败，secret 到不了端内 | **存量后端风险，本次不覆盖**：`TotpCode.compute` 的 `period > 0` 校验仅作纯防御，`Runtime.schedule()` 现有 warn 分支保留 |

### 3.6 安全设计

- **secret 生命周期**：仅 `/all`（及兜底 detail）响应 → 内存态 `ItemsRuntime`；**不落盘**（本次不引入持久化缓存）、不渲染、不打印
- **日志**：本地算码失败日志只带 item id + 错误摘要，禁止 secret；沿用现有 `%{private}s` 习惯
- **lint**：`createMac('SHA1')` 命中 `@security/no-unsafe-mac`（本工程配置为 **warn**，`code-linter.json5:21`）。SHA1 是 TOTP 互操作与后端一致性的硬要求 → 代码注释说明「RFC 6238 / 与后端 `build_noncompliant` 对齐」，**不放宽规则、不加禁用注释**
- 后端仍是 secret 唯一可信源，可随时重置；`/all` 下发 secret 属既有行为（微信方案已决策接受，见 `docs/totp-local-compute.md` 3.6）

### 3.7 性能与影响

| 指标 | 改造前 | 改造后 |
|------|--------|--------|
| 首屏请求（N 个账户） | 1 次 `/all` + N 次 `/detail` | 1 次 `/all` |
| 每周期请求 / DB 查询 | N 次 | 0 |
| 端内 CPU | — | 每账户每周期 1 次 HMAC-SHA1（微秒级） |
| 内存 | — | 每账户多一个 base32 字符串（16~64 字符） |

### 3.8 兼容性

- 后端零改动；微信主小程序继续消费响应里的 `code`，不受影响
- 华为元服务旧版本无影响（响应只增不减）；新老版本可并存
- 极端情况（响应无 `secret` 字段）→ `secret?: string` 可选声明 + 兜底 detail

### 3.9 本次不做

- 本地持久化缓存 / 冷启动离线亮码（另开改动）
- 服务端时间校准与时钟偏移检测（设备时间不准则码不准，与微信端同档）
- 后端 `create` 未校验 `period > 0`（扫码 URI 可注入 `period=0`，触发后端 `generate_code()` panic，见 3.5）——存量问题，建议单独提 issue，不在本次范围
- 详情页 secret 展示/掩码交互；创建页 secret 输入校验强化

## 4. 推进策略

```
Phase 0 契约/能力 spike（只读，约 0.2d）
├─ Node + node:crypto（可选 otpauth 9.5.2 复核）对齐 RFC 6238/4226 向量，产出黄金值表
├─ 实测 DevEco CLI 构建与本地单测命令可用性（证书与 SDK 本机已在位）
└─ 验证点：向量 6/6 一致 + CLI 命令快照落盘（不可用则改由人工 DevEco 验证）
Phase 1 端内算码能力（约 0.5d）
├─ utils/TotpCode.ets（base32 + HMAC-SHA1 + 动态截断）+ entry/src/test/TotpCode.test.ets + List.test.ets 注册
└─ 验证点：单测通过（或 CLI 不可用时标注人工验证）+ 黄金值对照
Phase 2 运行时集成（约 0.3d）
├─ types/Item.ets（secret）+ models/Runtime.ets（freshCode/rotate/resume/reload/schedule 五处）
└─ 验证点：构建通过 + grep 断言；真机与微信端同窗同码、飞行模式可用、增删改排序回归
Phase 3 发布（用户操作）
└─ 华为元服务版本提交审核
```

**回滚**：纯前端变更、无数据与后端变更；应用市场版本回退即恢复，后端无需回滚。

## 5. 风险与对策

| 风险 | 严重度 | 对策 |
|------|--------|------|
| 端内实现细节偏差 → 码与后端不一致（base32 末组、计数器高低位、偏移量） | 高 | Phase 0 黄金值表 + 单测覆盖 T=59 / 1111111109 / 1111111111 / 1234567890 / 2000000000 / 20000000000；真机与微信端同窗对照 |
| cryptoFramework 对空密钥必错（`convertKey` 0 字节非法） | 中 | 空/非法 secret → 回落 `/totp/detail` |
| `@security/no-unsafe-mac` 后续被收紧为 error | 中 | 注释说明为协议必需；必要时在 `code-linter.json5` 做**显式、可评审**的豁免（不静默绕过） |
| 设备时钟漂移/时区异常 → 码错误 | 中 | 与微信端同档；本地算码不引入新的错码源；记为后续增强项 |
| 存量账户 `config.period = 0`（扫码 URI 可注入）导致 `/all`、`/detail` 后端 panic、该用户列表整体不可用 | 中 | 本次不修（超出前端改造范围）；建议另开 issue：后端 `create` 校验 `period > 0`；端内 `period > 0` 校验仅作防御，不承诺该场景可用 |
| 异常账户离线不可用（兜底仍需网络） | 低 | 异常账户罕见，且为既有行为 |
| 华为侧回退需人工（应用市场） | 低 | 无数据/后端变更，回退成本低 |

## 6. 监控与可观测性

无上报通道（现状，本次不新建）。观测手段：

- `hilog` 记录端内算码失败（`LogDomain.MODELS`，仅 item id + 错误摘要，禁止 secret），示例：`端内算码失败，回退服务端: id=%{public}s`
- 后端已有请求日志，`/totp/detail` 调用量显著下降可作为改造生效的外部指标
- 告警：无（无基础设施，不虚构指标）

## 决策记录

| 编号 | 决策 | 结论 | 时间 |
|------|------|------|------|
| Q1 | 是否本次合并「本地持久化缓存 / 离线首屏」 | **不合并**：本次聚焦端内计算单一主题，缓存另开改动（拆两步更易评审） | 2026-09-30 |
| Q2 | 异常账户兜底策略；是否强化创建页 secret 校验 | 兜底按方案（端内失败 → `/totp/detail`）；创建页校验**维持现状**（≥1 字符，避免改动既有交互），异常账户由兜底覆盖 | 2026-09-30 |
| Q3 | `@security/no-unsafe-mac` 告警处理 | **直接接受**（仅代码注释说明 SHA1 为协议必需），不降级规则、不加行级禁用注释 | 2026-09-30 |
| Q4 | 验证环境 | Phase 0 尝试 DevEco CLI 构建/单测（写 `build/`、`.hvigor/` 缓存，均在忽略清单）；CLI 不可用则改由用户在 DevEco 手工验证 | 2026-09-30 |

## 附录 A：黄金值（Phase 0 待本地实测确认）

secret `GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ`（RFC 6238 的 ASCII `12345678901234567890`）、SHA1、6 位、period=30：

| T（epoch 秒） | 期望 6 位码 |
|---------------|-------------|
| 59 | `287082` |
| 1111111109 | `081804` |
| 1111111111 | `050471` |
| 1234567890 | `005924` |
| 2000000000 | `279037` |
| 20000000000 | `353130` |

来源：RFC 6238 Appendix B（8 位码）与 RFC 4226 Appendix D（6 位码）官方向量；状态标注为「推断需实测」，Phase 0 用 Node + otpauth 复核后落盘。

## 附录 B：调研依据

- 官方 HMAC 开发指导（一次性/分段/同步示例）：https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/security/CryptoArchitectureKit/crypto-compute-hmac.md
- 官方 API 参考（Mac/SymKeyGenerator 签名、原子化服务 API 12+ 标注）：https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-crypto-architecture-kit/js-apis-cryptoFramework.md
- 对称密钥生成与转换规格（HMAC 密钥 1~4096 字节）：https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/security/CryptoArchitectureKit/crypto-sym-key-generation-conversion-spec.md
- Code Linter `@security/no-unsafe-mac`（禁止 MAC 使用 SHA1 等弱哈希）：https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide_no-unsafe-mac
- TS→ArkTS 迁移指导（禁止 `@ts-ignore`；`.ets` 可 import `.ts/.js`）：https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/quick-start/typescript-to-arkts-migration-guide.md
- RFC 6238 测试向量：https://datatracker.ietf.org/doc/html/rfc6238#appendix-B ；RFC 4226 Appendix D：https://datatracker.ietf.org/doc/html/rfc4226#appendix-D
- 同仓先例：`docs/totp-local-compute.md`（微信 TOTP 小程序本地算码，PR #162）

## 修订记录

- 2026-09-30：落盘。`IItemConfig.secret` 定为**可选字段**（`secret?: string`），以兼容无 secret 的历史/异常响应，避免强制改造全部字面量；Q1~Q4 决策见「决策记录」。
- 2026-09-30：纯计算逻辑从 `utils/TotpCode.ets` 拆出为 `utils/TotpMath.ets`（无系统 kit 导入），使 `entry/src/test` 的本地单测可加载；行为与对外 API（`TotpCode.compute`）不变。
- 2026-09-30：plan-reviewer 首轮审查后修订——3.1 补 `HMAC` 规格选择约束（禁用 `HMAC|SHA1`）与 SHA1 支持结论的官方原文出处；3.3 新增密钥规格条目；3.5 修正 `period = 0` 场景（端内不可达，属存量后端 panic 风险）与「1 字符 secret」失真描述（入库只可能是空串或规范 base32）；3.9 与第 5 节记录 `period = 0` 存量风险为不在本次范围；修正 `api/Totp.ets`、`create/Index.ets` 行号引用。
- 2026-09-30：plan-reviewer 第 2 轮复审结论为「**可执行**」（BLOCKER=0、MAJOR=0），设计方案本轮未再改动；第 2 轮提出的 5 条 MINOR 均为 plan 文档文本/验收措辞修正，过程见 `docs/implementation/huawei-totp-local-compute.md` 修订记录。
