# 华为元服务 MFA：安全体验（防截屏 / 应用锁）

> **时间**：2026-10-11
> **作者**：DeepSeek V4.1 Flash + yansongda
> **状态**：经过人工审核确认
> **范围**：仅 `huawei/atomicservice/MFA` 元服务（微信端 `yansongda` / `totp` 不在范围）
> **配套执行计划**：`docs/implementation/2026-10-11-huawei-mfa-security-experience.md`

## 1. 背景与问题

**现状**（均已读源码验证）：

- 元服务 `huawei/atomicservice/MFA` 的应用主页面（`pages.json` 注册的唯一页面）是 `pages/Home.ets:23-31`：`Navigation(this.pages, { name: 'index' })` + `NavPathStack` 容器；业务页面全部是 `routes.json` 注册的 `NavDestination`；首屏 `pages/index/Index.ets` 展示 TOTP 明文动态码。（服务卡片页 `pages/form/Form2x2.ets:15` 也带 `@Entry`，由 `form_config.json` 声明、不在 `routes.json`，与本方案无关。）
- `{ name: 'index' }` 已确认为 `HomePathInfo`（`Navigation` 的**首页 NavDestination** 声明，API 20+；本机 SDK 核实）→ 首屏 `Index` 由 `Navigation` 直接渲染，不占导航栈。
- 应用生命周期钩子集中在 `ability/EntryAbility.ets`：`onWindowStageCreate:37-59` 内 `loadContent('pages/Home')` 并在回调里 `PersistenceV2.globalConnect`；`onForeground:64-67` / `onBackground:69-72` 已用于暂停/恢复端内算码定时器（`ItemsRuntime.resumeAll/stopAll`）。
- 持久化两条既有路径：认证信息走 `PersistenceV2`（`models/Auth.ets`）；跨进程快照走 `preferences` 库 `mfa_form`（`utils/Form.ets`，模式为 `getPreferencesSync` + `putSync` + `flushSync`）。
- `module.json5:52-66` 当前只声明 `INTERNET`、`CAMERA`；`build-profile.json5` 声明 `compatibleSdkVersion/targetSdkVersion = 6.1.0(23)`；`AppScope/app.json5`：`bundleType: atomicService`，`versionName 1.5.1`。
- 「我的」页 `pages/user/Detail.ets:46-102` 已是设置聚合页（InfoCard 分三组：个人资料 46-72 / 账号信息 74-82 / 更多 84-102）。

**困境**：

1. 验证码是**一次性凭据**，但当前截图、录屏、多任务卡片缩略图都能完整取走屏幕上的 6 位码。
2. 元服务「即用即走」，点卡/点图标即可拉起，**没有"进门一道锁"**；系统锁屏是设备级，管不到单个服务。
3. 「我的」页只有资料类设置，**没有任何安全开关**，用户无法按需加强保护。
4. 平台能力存在真机不确定性：`setWindowPrivacyMode` 在元服务有官方 `@atomicservice [since 12]` 标注（本机 SDK 已核实），但社区存在一例元服务真机「不生效」反例（见 §5 R1）→ 需真机 PoC 才能决定是否上线。

**目标**（约束条件）：

- **零后端改动**（无接口/协议/数据库变更）
- **零服务卡片改动**（卡片只展示账号数，不含验证码，天然不在保护范围）
- **默认安全**：防截屏默认开启；应用锁默认关闭、由用户主动开启
- **不可能被绕过**：锁定态覆盖一切可交互内容，不依赖导航栈（返回键、弹栈、卡片意图均不能穿透）
- **不可能被锁死**：设备凭据被删除/缺失时自动退出锁定态并关闭应用锁
- **可一键回退**：两功能独立开关、独立可发布、无数据迁移

## 2. 整体方案

**核心思路**：**在 `EntryAbility` 的窗口与生命周期节点集中接管两件事 —— ① 把主窗口设为隐私窗口（防截屏/防录屏/防多任务快照）；② 用系统统一用户认证控件在窗口顶层盖一层"锁定态"。** 两者由一个持久化的安全设置模型驱动；页面只负责「显示开关」与「显示锁屏」，不直接调用窗口 API 与认证 API。

```
                        ┌──────────────────────────────────────────┐
   preferences          │            models/Security.ets           │
   (库 mfa_security) ◀──┤  Security {screenProtect, appLock}   持久化│
                        │  AppLock  {locked, backgroundAt}    进程内 │
                        └────┬──────────────┬───────────────┬──────┘
                   ① 读设置 │    ② 订阅状态 │   ③ 变更状态   │
                            ▼              ▼               ▼
              pages/user/Detail.ets   components/       ability/EntryAbility.ets
              ┌──────────────┐        LockScreen.ets    ┌──────────────────────┐
              │  安全        │        ┌────────────┐     │ onWindowStageCreate  │
              │ 防截屏  [●]  │        │   已锁定    │     │ onForeground         │
              │ 应用锁  [○]  │        │  [ 解锁 ]  │     │ onBackground         │
              └──────┬───────┘        └─────┬──────┘     └──────┬───────────────┘
                     │ 开启前先验证          │ userAuth              │
                     ▼                     ▼                       ▼
              models/Security        @kit.UserAuthenticationKit  utils/Privacy.ets
              (验证通过才落盘)        统一认证控件(人脸/指纹/PIN)   setWindowPrivacyMode
                                                                   ▲
                                              window.WindowStage.getMainWindowSync()
```

**文件结构**（`[新]` 新建 / `[改]` 修改 / `[不动]` 明确不改）：

```
huawei/atomicservice/MFA/
├── entry/
│   ├── oh-package.json5                                     [不动] 依赖已在（@yansongda/otp ^1.0.2）
│   └── src/main/
│       ├── module.json5                                     [改] 声明 PRIVACY_WINDOW + ACCESS_BIOMETRIC
│       ├── resources/base/element/string.json               [改] 新增 §3.7 共 16 条文案（93 → 109 条）
│       └── ets/
│           ├── ability/EntryAbility.ets                     [改] 3 个生命周期钩子接线（各 1-4 行）
│           ├── models/Security.ets                          [新] Security（设置·持久化）+ AppLock（运行态）
│           ├── utils/Privacy.ets                            [新] 隐私窗口唯一写入口（缓存 WindowStage）
│           ├── utils/LockPolicy.ets                         [新] 锁定/防抖判定纯函数（零 import、可单测）
│           ├── components/LockScreen.ets                    [新] 锁定遮罩（全屏、自动拉起验证）
│           ├── components/SettingCard.ets                   [新] 设置型卡片（标题 + 说明 + 开关）
│           ├── components/InfoCard.ets                      [不动] 被 index/Detail 共用，零回归风险
│           ├── pages/Home.ets                               [改] Stack 包裹 + 遮罩 + 返回键消费
│           └── pages/user/Detail.ets                        [改] 新增「安全」分组（2 行开关）
├── entry/src/test/LockPolicy.test.ets                       [新] 本地单测（无需设备）
├── entry/src/test/List.test.ets                             [改] 追加注册
├── entry/src/main/resources/base/profile/routes.json        [不动] 不新增任何页面
├── build-profile.json5                                      [不动] 含本机签名材料，禁止触碰
└── AppScope/app.json5                                       [不动] 版本号由发布流程处理
```

**关键设计取舍**（6 条，逐条给理由）：

| 取舍 | 选择 | 理由 |
|---|---|---|
| 锁屏是「新页面」还是「遮罩层」 | **遮罩层**（`Home.ets` 的 `Stack` 顶层条件渲染） | 页面方式需 push/pop 导航栈、处理重复入栈与返回键，且栈下方页面仍可能被 pop 暴露；遮罩层不触碰导航栈，底层 `Navigation` 保持挂载、状态零丢失，绕过面最小 |
| 锁屏与登录页的关系 | **正交**：`locked` 只由安全设置与前后台计时决定，与 `Authorization` 无关 | 若改成"登录成功才置锁"，则 token 过期/未登录期间应用锁形同失效，是绕过口；因此锁定态**不因登录状态而改变**。**代价（已接受）**：冷启动未登录且应用锁开启时，遮罩会与底层已自动发起登录流程的登录页（`Login.ets:57-71` 的 `onReady → auth`，含 `LoadingDialogV2` 弹窗）**并存**——解锁优先于登录，不存在安全泄露（未登录时列表为空），并存表现列入真机冒烟第 14 项 |
| 应用锁验证时机 | **冷启动必验 + 退后台 ≥ 60s 必验**（常量，v1 不做配置 UI） | 覆盖全部真实泄露场景；60s 能容忍"切短信/浏览器取码再回来"；不做 UI 可省 1 个选择器页面与 3 个分支 |
| 是否复用设备解锁结果 | **不使用** `reuseUnlockResult`（`ReuseMode` + ≤5 分钟复用） | 复用会让"设备已解锁但手机被他人拿走"这一主要威胁场景失效；官方能力已评估后放弃（见附录） |
| 隐私模式写入口 | **全局单一入口** `Privacy.apply()`，禁止页面级调用 | 官方 FAQ 记载「全局 + 页面级混用会互相破坏」（同一主窗口实例，页面 `onHide` 会把全局设置一并关掉）；单一入口从设计上排除该竞态 |
| 设置型卡片 | **新增 `SettingCard.ets`**，不改 `InfoCard.ets` | `InfoCard` 被 `pages/index/Detail.ets` 与 `pages/user/Detail.ets` 共用，改动有回归风险；仓库已有 `InfoCard`/`InputCard` 分文件维护的先例 |

## 3. 详细设计

### 3.1 安全设置模型与持久化

| 类 | 位置 | 存储 | 字段 | 语义 |
|---|---|---|---|---|
| `Security` | `models/Security.ets` | `preferences` 库 `mfa_security`（同步读写） | `screenProtect: boolean`（默认 `true`）<br>`appLock: boolean`（默认 `false`） | 用户设置，跨启动持久；`@ObservedV2` + `@Trace` 供 UI 观测 |
| `AppLock` | 同文件 | `AppStorageV2.connect`（进程内） | `locked: boolean`（`@Trace`，驱动遮罩）<br>`backgroundAt: number \| undefined`<br>`verifying: boolean`<br>`generation: number`（世代号）<br>`lastFinishedAt: number \| undefined`（上次验证结束时间戳，供防抖判定） | 运行态；进程结束即归零，`locked` 默认 `false` |

**存储内容**（库名 `mfa_security`）：

```json
{
  "screen_protect": true,
  "app_lock": false
}
```

**为什么用 `preferences` 而不是 `PersistenceV2`**：`PersistenceV2` 只能持久化 `@Trace` 字段，无法把运行态排除在外——`locked` 一旦落盘，冷启动会读到上次的"未锁定"态，是**安全 bug**；且它异步落盘、失败不可观测。`preferences` 的 `putSync + flushSync` 语义明确、异常可记日志，与既有 `utils/Form.ets` 模式一致。

**读写契约**：

| 场景 | 行为 |
|---|---|
| key 不存在（首次启动/从未设置） | 用默认值（`screenProtect=true`、`appLock=false`），**不写盘** |
| 读异常 | 用默认值 + `hilog.error`；**fail-open**（应用锁失效）——见 §3.5 |
| 写异常 | `hilog.error` + 立即回滚内存值 → UI 开关弹回原位（不允许"显示已开、实际未开"） |

### 3.2 防截屏（隐私窗口）

**唯一入口** `utils/Privacy.ets`：

```
Privacy.attach(stage: window.WindowStage)   // onWindowStageCreate 内缓存；规避 getLastWindow 的异步延迟竞态
Privacy.apply(on: boolean, cause: string)   // 唯一写入口；内部链式排队（Promise 串联），保证后调用者最终生效
```

```
apply(on, cause):
  attach 未调用 → 记 warn 并返回
  链式排队 → stage.getMainWindowSync().setWindowPrivacyMode(on)
    成功: hilog.info(utils/privacy, set, privacyMode=on, cause=cause)
    失败: hilog.error(utils/privacy, set_failed, code)   // 该 API 在 API 26 d.ts 仅列 201（无权限）/ 1300002（窗口状态异常），其余按通用失败处理
```

**调用点（4 处：1-3 在 Ability 层，4 在设置页——但 4 仍经 `Privacy.apply` 这一唯一入口，不构成页面级直调）**：

| # | 时机 | 值 | 目的 |
|---|---|---|---|
| 1 | `onWindowStageCreate` → `loadContent` 回调内 | `security.screenProtect` | 冷启动立即生效 |
| 2 | `onForeground` | `security.screenProtect` | 从后台返回时恢复用户设置 |
| 3 | `onBackground`（仅 `appLock=true`） | `true` | 临时遮挡**多任务卡片快照**（此刻屏幕上是 TOTP 明文码） |
| 4 | 设置页开关变更后 | 新值 | 用户即时可见 |

**权限**：`module.json5` 新增 `ohos.permission.PRIVACY_WINDOW`（normal / system_grant / 起始版本 9；API 11 起为 normal）。

### 3.3 应用锁

**验证参数**（固定，非用户可配）：

| 参数 | 值 | 依据 |
|---|---|---|
| `authParam.challenge` | `Uint8Array`（16 字节，`cryptoFramework.createRandom().generateRandomSync(16).data`） | 官方要求"必须使用安全随机数生成器"；>32 字节报 12500008 |
| `authParam.authType` | `getAvailableStatus` 探测后的**可用类型列表**（原序 `[PIN, FACE, FINGERPRINT]`） | 只传可用类型，避免 12500005（类型不支持）/ 12500010（未录入） |
| `authParam.authTrustLevel` | `ATL3` | 与应用锁风险匹配；ATL4 面向小额支付等更高风险，ATL2 偏低 |
| `authParam.skipLockedBiometricAuth` | `true` | 生物识别因连续失败被锁定时**跳过倒计时直接切 PIN**（API 20+）；否则用户要干等 |
| `authParam.reuseUnlockResult` | **不传** | 见 §2 取舍表 |
| `widgetParam.title` | 「验证身份以解锁」 | ≤500 字符；类型为 `string`（**不接受 `Resource`**），实现用 `context.resourceManager.getStringSync($r('app.string.lock_page_verify_title').id)`——本机 SDK 无 `resourceToString` 全局函数（官方指南示例中的它是示例工程内的自定义辅助函数） |
| `widgetParam.navigationButtonText` | **不传** | 传了会走"自定义认证"分支并返回 12500011；不传则由**系统自己**提供「切换到口令认证」按钮，正好实现"生物识别失败回退锁屏密码" |
| `widgetParam.uiContext` | **不传** | 仅 2in1 设备可用（API 18+）；手机恒走系统模态弹窗，传了无意义 |

**锁定判定（`utils/LockPolicy.ets` 纯函数 + `AppLock` 编排）**：

```
shouldRelock(appLock, backgroundAt, now, timeout = 60_000)
  = appLock && backgroundAt 存在 && now >= backgroundAt && now - backgroundAt >= timeout

shouldDebounceVerify(finishedAt, now, debounce = 3_000)
  = finishedAt 存在 && now >= finishedAt && now - finishedAt < debounce
  # finishedAt = 上一次验证**结束**时间戳；undefined（从未验证过）或时钟回拨（now < finishedAt）→ false（放行），
  # 否则首次验证会被自身防抖挡住 → 应用锁把用户永久锁死

locked 由三处驱动，规则单向（只变 true，除 unlock / 降级外）：
  冷启动        : locked = security.appLock          （AppLock.reset）
  onForeground  : shouldRelock(...) === true && !verifying → locked = true（只加锁，绝不解锁）
  unlock(成功)  : locked = false
```

**防锁死降级（R2，必须实现）**：`verify()` 第一步做能力探测，全部不可用即判定"设备已无可用凭据"：

```
① for t in [PIN, FACE, FINGERPRINT]: getAvailableStatus(t, ATL3)  不抛错 → 可用
② 可用列表为空 → 二次确认「设备是否真的没有任何凭据」（**必须 try/catch**）：
     try { enrolled = getEnrolledState(PIN) }            // 该 API 自身在未录入时抛 12500010
       credentialCount === 0  → 确认成立
     catch 12500010           → 确认成立（未录入即无凭据）
     catch 其他               → 兜底视为未确认
   ③ 确认成立 → 降级：locked = false（立即放行）+ appLock = false + 落盘
                hilog.error(models/security, disable, reason=no_credential)
                **Toast** 提示「设备未设置锁屏密码，应用锁已自动关闭」
                （不能用内联提示：unlock() 后遮罩下一帧即卸载，用户看不到）
                **已知边界**：既有 `utils/PromptAction.ets:81-83` 在「登录页位于导航栈顶」时会直接丢弃 Toast；
                冷启动「未登录 + 应用锁开启 + 设备无凭据」三条件叠加时该提示不可见（解锁行为不受影响，见 §4.1 冒烟第 14 项）
                落盘失败仅记 hilog.error(disable_persist_failed)，不阻塞解锁
   ④ 未确认（有凭据但当前不可用，如 PIN 过期）→ report(FAILED) + 定向提示
                **禁止**以空 `authType` 数组调用 `getUserAuthInstance`（行为未定义）
   ⑤ authParam.authType = 可用列表（保持 PIN → FACE → FINGERPRINT 优先级）
```

`on('result')` 收到 `NOT_ENROLLED(12500010)` 时同样处理：**重新探测**——列表为空才降级，非空则按普通失败处理（避免误关闭应用锁）。

**并发与重试约束（官方原文驱动）**：

| 约束 | 落地 |
|---|---|
| 「每个 `UserAuthInstance` 只能用于一次认证，无论成功失败」 | **每次验证新建实例**（`getUserAuthInstance` → `on('result')` → `start()` 三件套），禁止缓存 |
| 「避免同时发起多个认证请求，防止相互抢占」 | 全局 `verifying` 标志（发起置位、`on('result')` 清除）；`LockScreen.aboutToAppear` 自动触发与用户点击走**同一入口** |
| 「后续发起的认证请求优先完成，致使前置认证请求被强制取消」 | `shouldDebounceVerify` 命中（3 秒内）或已在验证中时：直接返回 `SKIPPED`、**不改变内联提示**（避免闪烁），仅记 `verify_skip` 日志；3 秒后用户可手动重试 |
| 「不允许三方应用在后台发起身份认证请求」 | 验证**只能由页面触发**（`LockScreen.aboutToAppear` / 用户点击），**禁止**在 `UIAbility.onForeground` 内发起 |
| 官方未提供"退后台是否自动取消认证"依据 | **主动兜底**：`onBackground` 内 `instance?.cancel()` + `verifying = false` + `generation++`（`on('result')` 回调比对世代号，丢弃旧结果） |

**验证结果契约**（`verify(context, onOutcome?)`；回调签名为 `(outcome: VerifyOutcome, code?: number) => void`，`code` 为原始 `userAuth.UserAuthResultCode`，供 UI 映射定向文案——见 §3.5）：

| `VerifyOutcome` | 触发条件 | 副作用 |
|---|---|---|
| `SUCCESS` | `UserAuthResultCode.SUCCESS` | `locked = false` |
| `CANCELED` | `CANCELED` / `TIMEOUT` / `CANCELED_FROM_WIDGET` | 无（保持锁定） |
| `FAILED` | `FAIL` / `LOCKED` / `PIN_EXPIRED` / `GENERAL_ERROR` / `BUSY` / `INVALID_PARAMETERS` / 枚举外未知码 | 无（保持锁定） |
| `SKIPPED` | 已在验证中 / 命中 3 秒防抖 | 无 |
| `NO_CREDENTIAL` | 探测为空 或 重新探测后为空 | `locked = false` + `appLock = false` + 落盘 |

**界面**（`pages/user/Detail.ets` 新增「安全」分组，位于「账号信息」之后、「更多」之前）：

```
「我的」
  ├─ 安全
  │    ├─ 防截屏                                     [Switch ●]     ← 默认开
  │    │   截屏与录屏时，应用内容将被系统遮挡
  │    └─ 应用锁                                     [Switch ○]     ← 默认关
  │        重新打开或离开 1 分钟后需验证身份
  ├─ 账号信息   …
  └─ 更多       …
```

**开关交互序列**：

```
点「应用锁」开关
  ├─ 关闭（isOn=false）: 直接 setAppLock(ctx, false) + 落盘（关闭安全功能无需验证）
  └─ 开启（isOn=true）:
       能力探测 → userAuth 验证（系统控件）
         ├─ SUCCESS ────────▶ setAppLock(ctx, true) + 落盘
         ├─ NO_CREDENTIAL ──▶ 保持 false + 提示「请先在系统设置中设置锁屏密码」
         └─ 其他 ───────────▶ 保持 false + 提示「验证未通过，应用锁未开启」
```

> `Toggle` 的 `isOn` 由模型真值驱动（不做乐观更新）。但 `Toggle({ isOn })` 是**构造参数而非响应式绑定**，而验证失败时模型值不变、`ForEach` key 也不变 → 条目不重建，**开关视觉可能恰恰停在用户拨开的 ON 位**。因此：**预期**不会停在开启态（真机冒烟第 13 项确认）；**若确认不复位**，按 §5 R7 的备选实现（整行 `onClick` 触发流程 + `Toggle` 置 `.enabled(false)` 只读呈现）执行。

### 3.4 锁屏遮罩

**新增 `components/LockScreen.ets`**（不注册路由，纯组件）：

```
┌────────────────────────────────────┐   ├ 布局：Stack 顶层，width/height 100%，
│            [应用图标 30%]           │   │  backgroundColor(sys.color.background_secondary)
│                                    │   │  expandSafeArea(SYSTEM, TOP|BOTTOM)
│              已锁定                 │   ├ aboutToAppear：AppLock.verify() 自动拉起
│      验证身份后可查看验证码          │   │  系统认证控件（无需用户再点一次）
│                                    │   ├ 失败/取消：停留遮罩 + 内联提示，可反复重试
│          ┌──────────┐              │   ├ 并发保护：verifying 期间 AppLock 直接返回 SKIPPED
│          │   解锁    │              │   └ 无凭据：提示 + 自动解锁（§3.3 防锁死）
│          └──────────┘              │
└────────────────────────────────────┘
```

**`pages/Home.ets` 改造**（唯一结构性改动）：

```
Stack() {
  Column() { Navigation(this.pages, { name: 'index' }) … }   // 原样保留，状态不丢
  if (this.appLock.locked) { LockScreen() }                   // 不透明遮罩，盖住一切
}.width('100%').height('100%')

onBackPress(): boolean { return this.appLock.locked; }        // 锁定期间消费返回键
```

**明确不处理的场景**（避免过度设计）：

- **卡片意图**（`index/create`、扫码）：锁定期照旧写入 `FormIntent` / 入栈，解锁后自然呈现，不需要门禁；
- **服务卡片内容**：只渲染账号数与入口文案，不含验证码；
- **系统弹窗穿透**：`openCustomDialog` 属 `UIContext` 级，理论可浮在遮罩之上；锁定期不产生新的网络刷新动作（端内算码为主），且弹窗文案不含验证码，泄露面为零（R4）。

### 3.5 降级策略（按环节）

| 环节 | 失败场景 | 行为 | 是否可接受 |
|---|---|---|---|
| 读设置 | `getPreferencesSync` 抛错 | 默认值（`screenProtect=true`、`appLock=false`）+ `hilog.error` | ✅ **刻意 fail-open**：无法区分"从未设置"与"读失败"，fail-closed 会让首次启动用户被关在门外 |
| 写设置 | `putSync/flushSync` 抛错 | 回滚内存值 + 开关弹回 + `hilog.error` | ✅ 用户看到真实状态 |
| 隐私模式 | `setWindowPrivacyMode` 抛错（201/1300002，或未文档化的通用异常） | 记错误日志；功能不生效但不影响其他功能 | ✅ 不弹窗骚扰；由 R1 真机 PoC 决定是否上线该功能 |
| 能力探测 | 三种认证方式全不可用 | **自动解锁 + 自动关闭应用锁** + 提示 | ✅ 防锁死的唯一可行解（R2） |
| 认证执行 | `FAIL` | 保持锁定 + 「验证失败，请重试」 | ✅ |
| 认证执行 | `CANCELED` / `CANCELED_FROM_WIDGET` | 保持锁定 + 可重试（3 秒防抖）；不配置 `navigationButtonText` → 正常路径下不会出现 `CANCELED_FROM_WIDGET` | ✅ |
| 认证执行 | `TIMEOUT` | 保持锁定 + 可重试 | ✅ |
| 认证执行 | `LOCKED` | 保持锁定 + 定向文案 `lock_page_locked_out`（「验证次数过多，请稍后再试」，由回调 `code` 映射） | ✅ 系统防暴力机制，不由应用绕过 |
| 认证执行 | `PIN_EXPIRED`（多数情况在**探测阶段**即被 `getAvailableStatus` 抛出，不会进入认证） | 有可用凭据时保持锁定；**无可用凭据时**按 §3.3 ④ 走 `FAILED` + 定向文案 `lock_page_pin_expired`（「锁屏密码已过期，请先更新」），需用户在系统设置更新密码后自愈 | ✅ 该场景无法由应用侧解锁（凭据确已失效），提示后由系统设置修复 |
| 认证执行 | `GENERAL_ERROR` / `BUSY` | 保持锁定 + 可重试 | ✅ |
| 认证执行 | `NOT_ENROLLED` | 重新探测：为空 → 降级；非空 → 按 `FAILED` 处理 | ✅ 避免误关闭应用锁 |
| 认证执行 | 枚举外的未知码 | 保持锁定 + 通用失败提示（按常量穷举，不写字面量） | ✅ 前向兼容 |
| 冷启动锁 + 未登录 | 无可用 `Authorization` | 遮罩立即出现（`locked` 与登录状态无关），底层登录页照常自动发起 `华为账号授权 + LoadingDialogV2`；解锁优先于登录，两者并存但互不阻塞，未登录时底层无任何验证码内容可泄露（§2 正交取舍、冒烟第 14 项） | ✅ |

### 3.6 关键契约（逐条标注来源）

| # | 契约 | 核实结果 |
|---|---|---|
| C1 | `Window.setWindowPrivacyMode` | `setWindowPrivacyMode(isPrivacyMode: boolean): Promise<void>`（另有 `AsyncCallback<void>` 重载）；`@permission ohos.permission.PRIVACY_WINDOW`；`@throws 201 / 1300002`（该 API 的全部文档化错误码）；**`@atomicservice [since 12]`**；`@since 9`；旧接口 `setPrivacyMode` 已标 `@useinstead` |
| C2 | `ohos.permission.PRIVACY_WINDOW` | 级别 **normal**、授权方式 **system_grant**、起始版本 9；**API 9-10 为 system_basic，API 11 起变更为 normal** |
| C3 | 隐私模式表现 | 窗口内容无法被截屏/录屏；录屏为纯黑、多任务卡片为白/隐私蒙层、应用自身 `snapshot()` 为白屏（官方文档 + 华为客服页）；**社区存在一例元服务真机「不生效」反例 → 待真机 PoC** |
| C4 | `WindowStage.getMainWindowSync(): Window` | **`@atomicservice [since 11]`**，`@since 9`；官方 FAQ 推荐用它规避 `getLastWindow` 异步延迟导致的隐私模式偶发失效 |
| C5 | `userAuth.getUserAuthInstance(authParam, widgetParam): UserAuthInstance` | 全模块条目 **`@atomicservice [since 12]`**；`on('result')` / `off` / `start()` / `cancel()` |
| C6 | `AuthParam` | `challenge: Uint8Array`（≤32B，建议 crypto framework 随机数）、`authType: UserAuthType[]`（PIN=1 / FACE=2 / FINGERPRINT=4）、`authTrustLevel: AuthTrustLevel`（ATL1=10000 / ATL2=20000 / ATL3=30000 / ATL4=40000）、`reuseUnlockResult?`(12+)、**`skipLockedBiometricAuth?: boolean`(20+)** |
| C7 | `WidgetParam` | `title`（非空 ≤500）、`navigationButtonText?`（≤60，**默认不显示**）、**`uiContext?: Context`（仅 2in1，默认系统模态弹窗）** |
| C8 | `ohos.permission.ACCESS_BIOMETRIC` | 级别 **normal**、授权方式 **system_grant**、起始版本 6；须在 `module.json5` 声明 |
| C9 | `UserAuthResultCode` | **`SUCCESS = 12500000`**（逐字核实）；`FAIL 12500001` / `GENERAL_ERROR 12500002` / `CANCELED 12500003` / `TIMEOUT 12500004` / `TYPE_NOT_SUPPORT 12500005` / `TRUST_LEVEL_NOT_SUPPORT 12500006` / `BUSY 12500007` / `INVALID_PARAMETERS 12500008`（20+）/ `LOCKED 12500009` / `NOT_ENROLLED 12500010` / `CANCELED_FROM_WIDGET 12500011`（10+）/ `PIN_EXPIRED 12500013`（12+）；**无 12500012、无 12500014** |
| C10 | `getAvailableStatus(authType, authTrustLevel): void` | 同步、返回 void、不支持时抛错（201/401/12500002/12500005/12500006/12500010/12500013） |
| C11 | `MAX_ALLOWABLE_REUSE_DURATION = 300000`（5 分钟） | 存在（12+）；本方案**不使用** |
| C12 | 统一用户认证控件 | 生物认证失败后显示按钮，点击可从生物认证切换到 `AuthParam.authType` 中的其他口令认证类型 |
| C13 | `getEnrolledState(authType): EnrolledState` | `{ credentialDigest, credentialCount }`（12+）；`@permission ohos.permission.ACCESS_BIOMETRIC`；**查 `PIN` 时返回整体状态而非个数** |
| C14 | `UserAuthInstance` 生命周期 | 源码原文："Each `UserAuthInstance` can be used for authentication only once. After the authentication is complete (regardless of whether it is successful or fails), the instance cannot be used again."；`start()` 权限自 API 20 起为 `ACCESS_BIOMETRIC` **或** `USER_AUTH_FROM_BACKGROUND` |
| C15 | 后台发起认证 | 官方总则禁止三方应用在后台发起身份认证；`onForeground` 时已属前台（不违反）；"退后台是否自动取消认证"**未找到官方依据** → 以主动 `cancel()` 兜底 |
| C16 | 前台状态查询 API | 普通应用/元服务**无**可用 API（`appManager.getForegroundApplications` 为 `@systemapi`）→ 触发点只能落在 `UIAbility` 生命周期 |
| C17 | `Navigation(pathInfos, homeDestination: HomePathInfo)` | `HomePathInfo { name: string; param?: Object }`（20+，`@atomicservice`）→ 确认 `Home.ets:25` 的 `{name:'index'}` 是首页声明，`Index` 不占导航栈 |

**来源标注**（避免"源码级核实"言过其实）：

| 来源类型 | 条目 | 说明 |
|---|---|---|
| 本机 SDK d.ts 逐字核实 | C1 / C4 / C5 / C6 / C7 / C8 / C9 / C10 / C11 / C13 / C14 / C17 | 行号精确（`@ohos.userIAM.userAuth.d.ts:1047/1059/1111/1333/1416/1465/1889/1899`、`@ohos.window.d.ts:6873`、`navigation.d.ts:1355/1451`） |
| 本机 SDK 权限定义文件 | C2 / C8（权限级别部分） | `toolchains/lib/PermissionDefinitions.json` |
| 本机 SDK 中**不存在**该 API → 结论由"缺席"成立 | C16 | `appManager.getForegroundApplications` 不在公共 d.ts 中（仅 previewer 二进制内含），故普通应用/元服务无前台查询 API |
| 官方指南/文档主张（d.ts 无对应文本） | C3（录屏纯黑、`snapshot()` 白屏）、C12（失败后切换口令按钮）、C15（后台发起认证总则）、C2（API 9-10 级别变迁） | 已在 §5 以真机冒烟与设计约束对冲 |
| 社区实践（单一来源，弱证据） | C3 的"元服务真机不生效"反例 | 已列为 R1 与冒烟第 5 项强制门槛 |

**SDK 版本适配**：本机 SDK = HarmonyOS 26.0.0（API 26），项目声明 `compatibleSdkVersion = 6.1.0(23)`。本方案用到的最高 API 为 20（`skipLockedBiometricAuth`、`HomePathInfo`），**全部 ≤ 23** ✅。

### 3.7 新增文案（`resources/base/element/string.json`，93 → 109 条）

| name | 值 |
|---|---|
| `user_detail_page_security` | 安全 |
| `user_detail_page_screen_protect` | 防截屏 |
| `user_detail_page_screen_protect_desc` | 截屏与录屏时，应用内容将被系统遮挡 |
| `user_detail_page_app_lock` | 应用锁 |
| `user_detail_page_app_lock_desc` | 重新打开或离开 1 分钟后需验证身份 |
| `user_detail_page_app_lock_enable_failed` | 验证未通过，应用锁未开启 |
| `user_detail_page_app_lock_no_credential` | 请先在系统设置中设置锁屏密码 |
| `lock_page_locked` | 已锁定 |
| `lock_page_hint` | 验证身份后可查看验证码 |
| `lock_page_unlock` | 解锁 |
| `lock_page_verify_title` | 验证身份以解锁 |
| `lock_page_failed` | 验证失败，请重试 |
| `lock_page_locked_out` | 验证次数过多，请稍后再试 |
| `lock_page_no_credential` | 设备未设置锁屏密码，应用锁已自动关闭 |
| `user_detail_page_setting_failed` | 设置保存失败，请重试 |
| `lock_page_pin_expired` | 锁屏密码已过期，请先更新 |

### 3.8 性能与影响分析

| 维度 | 改造前 | 改造后 | 说明 |
|---|---|---|---|
| 冷启动额外动作 | 0 | 1 次 `preferences` 同步读（毫秒级）+ 1 次 `setWindowPrivacyMode` | 均在 `loadContent` 回调内，不阻塞首帧 |
| 前台恢复额外动作 | `resumeAll()` | `resumeAll()` + 1 次隐私模式调用 + 1 次时间戳比较 | 无网络、无磁盘 |
| 退后台额外动作 | `stopAll()` | `stopAll()` + 1 次隐私模式调用（+ 可能的 `cancel()`） | 无网络、无磁盘 |
| 内存 | — | 2 个轻量模型（5 个字段） | 可忽略 |
| 网络 / 后端 | — | **零改动** | — |
| 包体 | — | 2 个组件 + 3 个模型/工具文件 + 2 条权限 | 可忽略 |
| 对 `Index` 定时器 | 每秒刷新验证码 | **不变**（锁定期间底层仍在算码，遮罩不透明不可见） | 刻意不改，避免"解锁后列表不刷新"的新状态机 |

### 3.9 时序（完整）

```
冷启动 ────────────────────────────────────────────────────────────────────
 UIAbility.onCreate
 UIAbility.onWindowStageCreate
   └─ loadContent('pages/Home') → 回调内（既有 try/catch 之后新增）
        ├─ Security.shared().load(context)      读 mfa_security → screenProtect / appLock
        ├─ Privacy.attach(windowStage)          缓存主窗口
        ├─ Privacy.apply(screenProtect, 'cold_start')   ① 防截屏立即生效
        └─ AppLock.shared().reset(appLock)      locked = appLock
 UIAbility.onForeground                        （冷启动时 backgroundAt 为空）
   ├─ ItemsRuntime.resumeAll()                                       既有
   ├─ Privacy.apply(screenProtect, 'foreground')                     ② 恢复用户设置
   └─ AppLock.shared().onForeground()          shouldRelock → false → 不改锁态
 Home.onPageShow → redirectLoginPage()（未登录时）                     既有
 LockScreen.aboutToAppear
   ├─ probe()：getAvailableStatus(PIN | FACE | FINGERPRINT, ATL3)
   │    └─ 全不可用 + getEnrolledState(PIN) 二次确认（try/catch；抛 12500010 亦视为确认）
   │         → NO_CREDENTIAL：自动解锁 + 关闭应用锁 + 提示
   └─ 新建 UserAuthInstance → on('result') → start()
        └─ SUCCESS → AppLock.unlock() → locked = false → 遮罩消失

退后台 / 回前台 ────────────────────────────────────────────────────────────
 UIAbility.onBackground
   ├─ ItemsRuntime.stopAll()                                         既有
   ├─ AppLock.shared().onBackground()
   │    ├─ backgroundAt = Date.now()
   │    ├─ instance?.cancel() + verifying = false + generation++
   │    └─ （不改变 locked：未锁的保持未锁，已锁的保持已锁）
   └─ appLock=true → Privacy.apply(true, 'background')               ③ 遮挡多任务卡片
 UIAbility.onForeground
   ├─ ItemsRuntime.resumeAll()                                       既有
   ├─ Privacy.apply(screenProtect, 'foreground')                     ② 恢复用户设置
   └─ AppLock.shared().onForeground()
        └─ shouldRelock(appLock, backgroundAt, now) && !verifying
             → locked = true（遮罩出现并自动拉起验证）；清空 backgroundAt
```

> 顺序安全性说明：`Security.shared()` / `AppLock.shared()` 在未 `load` 时给出默认值（`appLock=false`，即不锁），`Privacy.apply` 在 `attach` 前调用会记 `warn` 并返回——即使 `onForeground` 早于 `onWindowStageCreate` 触发也不会产生错误状态；`onWindowStageCreate` 的回调内会再显式应用一次。

### 3.10 可测性（本地单测，无需设备）

`AppStorageV2` / `@kit.ArkUI` 在本地单测环境不可用，因此把最易写错的阈值/防抖判定抽为零依赖纯函数（**`utils/LockPolicy.ets` 无任何 import**）：

```
// utils/LockPolicy.ets
export const LOCK_TIMEOUT_MS: number = 60000;
export const VERIFY_DEBOUNCE_MS: number = 3000;
export function shouldRelock(appLock: boolean, backgroundAt: number | undefined, now: number,
                             timeout: number = LOCK_TIMEOUT_MS): boolean;
export function shouldDebounceVerify(finishedAt: number | undefined, now: number,
                                     debounce: number = VERIFY_DEBOUNCE_MS): boolean;
```

`entry/src/test/LockPolicy.test.ets`（`@ohos/hypium`，工程级 `devDependencies` 已含 1.0.21）用例：

| 用例 | 期望 |
|---|---|
| `shouldRelock(false, 任意)` | `false` |
| `shouldRelock(true, undefined, now)` | `false`（冷启动锁态由 `reset` 决定） |
| `shouldRelock(true, now-59_999, now)` | `false` |
| `shouldRelock(true, now-60_000, now)` | `true` |
| `shouldRelock(true, now+1000, now)`（时钟回拨） | `false` |
| `shouldDebounceVerify(undefined, now)` | `false`（从未验证过） |
| `shouldDebounceVerify(now-2_999, now)` | `true` |
| `shouldDebounceVerify(now-3_000, now)` | `false` |
| `shouldDebounceVerify(now+1_000, now)`（时钟回拨） | `false`（放行；否则时钟回拨会把用户挡在门外） |

## 4. 推进策略

**两个阶段，各自可独立上线/独立回滚**（防截屏先做：它是应用锁真机 PoC 的探路者，共用同一套权限与窗口链路）。

```
Task 0（改动前基线，只读 + 一次性装依赖）
  ├─ ohpm install（联网，生成 entry/oh_modules；oh_modules 已在 .gitignore）
  ├─ hvigorw --mode module -p product=debug -p module=entry@default assembleHap
  │    └─ 抓「改动前可编译」基线；若 API 23 声明与 API 26 SDK 不兼容 → 在此暴露
  └─ 实测本地单测的 CLI 任务名（保底路径：DevEco 内 Run entry/src/test/LocalUnit.test.ets）

阶段 1（防截屏）
  ├─ 任务：module.json5 权限 + utils/Privacy.ets + Security 持久化 + EntryAbility 接线 + 设置页开关 + 文案
  ├─ 验证：本机 assembleHap 通过；真机截屏/录屏/多任务卡片/开关关闭四场景
  └─ 发布：v1.6.0；若真机确认元服务不生效 → 隐藏开关（代码保留）后发布

阶段 2（应用锁）
  ├─ 任务：LockPolicy + 单测 + AppLock 运行态 + LockScreen + Home 遮罩 + 前后台钩子 + 返回键消费 + 设置项
  ├─ 验证：本机 assembleHap + LockPolicy 单测通过；真机 14 项冒烟（§4.1）
  └─ 发布：v1.7.0
```

**说明**：本方案的两个阶段在**同一个执行计划内一次实现完**（`docs/implementation/2026-10-11-huawei-mfa-security-experience.md`），"阶段"用于区分**发布批次**与**回滚粒度**，不作为实施顺序的硬约束；打 tag / AGC 上架由 `release-huawei-atomicservice` skill 另行处理。

**回滚方案**：

| 类型 | 操作 | 生效时间 |
|---|---|---|
| 正常回滚（防截屏） | `Security` 的 `screenProtect` 默认值改 `false`，并隐藏设置页该行 | 下次发版 |
| 正常回滚（应用锁） | `AppLock` 的 `locked` getter 首行 `return false`（或 `Security.appLock` 读取处强制 `false`）——注意 `AppLock` 只有 `locked` getter，**没有** `isLocked()` 方法 | 下次发版 |
| 紧急回滚 | 元服务**不支持版本回退**，只能发新版把上述开关归零；用户端无残留数据（`mfa_security` 两个布尔值不影响运行） | 下一版审核通过后 |
| 环境回滚 | feature 分支 revert（无后端、无迁移，revert 即彻底回滚） | 立即 |

### 4.1 真机冒烟清单（14 项，由人工执行 —— 本机无设备）

| # | 场景 | 期望 |
|---|---|---|
| 1 | 开启防截屏后截屏 | 截图中的元服务内容被遮挡（黑/蒙层），且系统无异常提示 |
| 2 | 开启防截屏后录屏 | 录得的元服务区域为纯黑/蒙层 |
| 3 | 退后台看多任务卡片 | 卡片缩略图被遮挡（白/隐私蒙层） |
| 4 | 关闭防截屏后截屏 | 正常截到内容 |
| 5 | **元服务是否支持隐私窗口（R1 关键项）** | `setWindowPrivacyMode` 真机生效（不生效则本功能不上线） |
| 6 | 开启应用锁（首次） | 弹出系统认证控件；验证成功后开关变开；设置落盘（杀进程重进仍为开） |
| 7 | 冷启动 | 锁定遮罩出现并自动拉起认证；验证成功后进入列表 |
| 8 | 退后台 30 秒回来 | **不**要求验证 |
| 9 | 退后台 70 秒回来 | 要求验证 |
| 10 | 连续验证两次（验证实例复用回归，R14） | 两次都能正常弹出并成功 |
| 11 | 删除系统锁屏密码/人脸指纹后再启动 | 自动解锁 + 自动关闭应用锁 + 提示（不被锁死，R2） |
| 12 | 锁定期按返回键 / 点卡片意图 | 返回键不穿透（底层页面不可操作）；解锁后落在预期页面 |
| 13 | 连续两次「点开应用锁开关 → 取消系统验证」（R7） | 每次都回到关闭视觉，不残留"开启"外观 |
| 14 | 冷启动「未登录 + 应用锁开启」 | 遮罩优先出现且可正常解锁；底层登录流程（华为账号授权 / loading 弹窗）并存但不阻塞；解锁后能正常进入列表或登录页，无卡死。**若同时叠加第 11 项（设备无凭据）**：解锁照常发生，但降级提示可能被登录页栈顶吞掉（既有 `Toast` 行为，见 §3.3 ③）——属已知边界，不算失败 |

## 5. 风险与对策

| # | 风险 | 严重度 | 对策 |
|---|---|---|---|
| R1 | `setWindowPrivacyMode` 在元服务真机不生效（官方标注 API 12+ 支持元服务 vs 社区一例反例） | **高** | **真机冒烟第 5 项为发布前强制门槛**；不生效则隐藏「防截屏」开关、本功能不上线，应用锁不受影响 |
| R2 | 应用锁把用户**锁死**（凭据被删 / 无锁屏密码 / 密码过期） | **高** | `getAvailableStatus` 三类型探测 + `getEnrolledState` 二次确认 → 自动解锁 + 自动关闭应用锁 + 提示（§3.5 唯一可接受路径） |
| R3 | 设置读取失败 → 应用锁静默失效（fail-open） | 中 | **刻意接受**：无法区分"从未设置"与"读失败"，fail-closed 会导致首次启动被关在门外；以 `hilog.error` 留痕 + 真机回归覆盖 |
| R4 | 系统弹窗/自定义弹窗浮在遮罩之上（`openCustomDialog` 属 `UIContext` 级） | 中 | 锁定期不产生新的网络刷新动作；弹窗文案不含验证码 → 泄露面为零；不为此增加拦截层 |
| R5 | 系统认证控件与遮罩叠加表现未知：手机端**恒为系统模态弹窗**（`uiContext` 仅 2in1 可用，**不能作为手机兜底**），官方未承诺是否全屏；官方亦未给出「退后台是否自动取消认证」依据 | 中 | 真机验证（冒烟 6/7/12）；退后台由**主动 `cancel()`** 兜底；若控件被遮挡或表现异常 → 回退为 `bindContentCover`（`ModalTransition.NONE`）遮罩 + 认证前收起业务弹层（**不改认证参数**） |
| R6 | 生命周期时序导致误锁/漏锁（`onForeground` 冷启动时也会触发） | 中 | 规则单向：`onForeground` **只加锁、绝不解锁**；冷启动锁态只由 `AppLock.reset(appLock)` 决定；`backgroundAt` 判定后清空 |
| R7 | 用户取消系统验证 → 开关视觉未复位（`Toggle.isOn` 与模型不一致） | 低 | `isOn` 由模型真值驱动、不做乐观更新；真机回归（冒烟 13）；若仍不复位 → 备选实现：整行 `onClick` 触发流程 + `Toggle` 置 `.enabled(false)` 只读呈现 |
| R8 | AGC 审核/客服排查时截屏黑屏，被误判为崩溃 | 低 | 提交说明中注明"隐私窗口特性"；必要时审核期用关闭防截屏的测试包 |
| R9 | 未来有人在页面级再写 `setWindowPrivacyMode` → 复现官方 FAQ 的"全局防截屏失效"故障 | 中 | ① `utils/Privacy.ets` 文件头注释（执行计划 Task 2）；② `huawei/atomicservice/MFA/AGENTS.md` 的「开发约束」节新增一句硬约束（执行计划 Task 1）。隐私模式**只允许**经 `Privacy.apply` 修改 |
| R10 | `onBackPress` 在 `@Entry @ComponentV2` 页面行为不符预期 | 低 | 真机验证（冒烟 12）；即使失效也不影响安全性（仅体验），可退化为不消费返回键 |
| R11 | `@Trace locked` 未按预期驱动 `Home` 重渲染（V2 观测边界） | 中 | 遮罩依赖 `Home` 内 `@Local appLock` 读取 `locked`；真机验证；兜底改为 `bindContentCover` |
| R12 | 应用锁开启后每次冷启动都弹系统认证，被用户视为骚扰 | 中 | 默认关闭、用户主动开启；设置项副标题明确触发规则；不做后台自动重锁（仅 60s 阈值） |
| R13 | 本机 SDK 为 API 26，项目声明 `compatibleSdkVersion = 6.1.0(23)` → 兼容性未实测 | 中 | Task 0 先跑 `assembleHap` 抓基线；不兼容则装对应 API 23 SDK 或抬 `compatibleSdkVersion`（**需人工决策，不自行改**） |
| R14 | 认证实例复用（官方：每实例仅能用一次）导致第二次解锁静默失败 | 中 | 每次验证新建实例；`verifying` 标志 + 3 秒防抖；真机冒烟第 10 项回归 |
| R15 | `skipLockedBiometricAuth`（20+）与「生物识别被锁定 → 切 PIN」的真机行为 | 低 | 真机验证；异常则置 `false` 退回系统默认倒计时 |
| R16 | `ohpm install` 需联网 + `~/.ohpm` 未初始化 | 低 | Task 0 一次性完成；失败则用 DevEco 的 Sync 兜底 |
| R17 | 本机无真机，窗口/认证行为无法自动化验证 | 中 | 三层验收（本机编译 → 本地单测 → 真机冒烟 14 项）；真机清单列为发布前强制人工门槛 |

## 6. 监控与可观测性

复用现有 `hilog`（`LogDomain` 已含 `ABILITY=0`、`UTILS=1`、`MODELS=2`），不新增上报通道：

```jsonc
{"domain":2,"tag":"models/security","event":"load","screenProtect":true,"appLock":true}
{"domain":1,"tag":"utils/privacy","event":"set","privacyMode":true,"cause":"background"}
{"domain":1,"tag":"utils/privacy","event":"set_failed","code":201}
{"domain":2,"tag":"models/security","event":"lock","reason":"cold_start|timeout","elapsedMs":92500}
{"domain":2,"tag":"models/security","event":"unlock","result":12500000,"authType":4}
{"domain":2,"tag":"models/security","event":"disable","reason":"no_credential"}
{"domain":2,"tag":"models/security","event":"verify_skip","reason":"in_flight|debounce"}
```

| 指标 | 计算方式 | 关注阈值 |
|---|---|---|
| 隐私模式调用失败率 | `utils/privacy` 的 `set_failed` 计数 | > 0 即排查（元服务兼容性，R1） |
| 应用锁因无凭据自动关闭次数 | `models/security` 的 `disable(no_credential)` 计数 | > 0 需评估探测逻辑是否过严 |
| 解锁失败分布 | `models/security` 的 `unlock` 结果码分布 | `GENERAL_ERROR`/`BUSY` 占比高说明调用时机有问题 |
| 冷启动锁定次数 | `lock(cold_start)` / 启动次数 | 与开关开启率对齐，验证设置读取链路 |
| 验证被跳过次数 | `verify_skip` 计数 | 异常偏高说明有重复触发（R14） |
| 降级落盘失败次数 | `models/security` 的 `disable_persist_failed` 计数 | > 0 表示「无凭据降级」未能持久化，下次冷启动会重演降级（不会锁死，但提示失真） |

## 7. 待确认问题

无（原 3 项已确认：① 范围仅华为元服务；② 防截屏默认开启且提供开关；③ 应用锁阈值固定 60 秒、v1 不做配置 UI；`ohpm install` 已授权）。

## 8. 变更记录（里程碑）

| 时间 | 变更 |
|---|---|
| 2026-10-11 | **复审修订（R2 轮）**：① `VerifyOutcome` 回调增加 `code` 通道，使 §3.3/§3.5 承诺的 `LOCKED`/`PIN_EXPIRED` 定向文案真正可达（新增文案 `lock_page_pin_expired`，15 → 16 条）；② 防锁死降级的提示改为 **Toast**（`unlock()` 后遮罩即卸载，内联提示不可见）并检查落盘返回值；③ `shouldDebounceVerify` 参数名统一为 `finishedAt` 并同步「时钟回拨 → 放行」分支（与执行计划实现一致）；④ §3.1 字段表补 `lastFinishedAt`；⑤ `AppLock.isLocked()` → `locked` getter（回滚指引原本引用不存在的 API）；⑥ §1 修正「唯一 `@Entry`」与 `Detail.ets` 锚点、§2 修正 `Login.ets` 锚点、§3.2 修正「全部在 Ability 层」措辞；⑦ §6 增加 `disable_persist_failed` 指标 |
| 2026-10-11 | **初审修订（R1 轮）**：① 修正 §2「锁屏与登录页关系」的理由（原文与实现相反：遮罩与底层登录流程**并存**，非"登录后才置锁"）；② `getEnrolledState` 补 try/catch（该 API 在未录入时自抛 12500010）并禁止以空 `authType` 调用 `getUserAuthInstance`；③ `widgetParam.title` 明确必须传 `string`（SDK 无 `resourceToString`）；④ C1 错误码收敛为该 API 文档化的 201/1300002；⑤ §3.6 增加「来源标注」表；⑥ 文案 14 → 15 条；⑦ 冒烟 13 → 14 项 |
| 2026-10-11 | 方案定稿（v3）：范围锁定华为 MFA 元服务；契约由外部镜像改为**本机 SDK API 26 d.ts 源码级核实**（C1–C17）；采纳 `skipLockedBiometricAuth`；锁定「手机端 `uiContext` 不可用、不能作为兜底」；认证实例单次使用 + in-flight + 3 秒防抖 + 退后台主动 `cancel()` 纳入设计；新增 `utils/LockPolicy.ets` 纯函数与本地单测；`InfoCard` 改为**不改**、新增 `components/SettingCard.ets`；文案 16 条；新增 2 个权限 |

## 附录：本次不做（已评估后主动放弃）

| 项 | 不做理由 |
|---|---|
| 微信端（`yansongda`、`totp`）防截屏 | 按确认范围仅华为 MFA；微信端无「锁屏密码」等价能力，需另起方案 |
| `reuseUnlockResult`（≤5 分钟复用设备解锁结果） | 会让"设备已解锁但手机被他人拿走"这一主要威胁场景失效 |
| `WidgetParam.uiContext`（应用模态弹窗） | 仅 2in1 设备可用，手机无收益 |
| `USER_AUTH_FROM_BACKGROUND` 权限（后台发起认证） | 本方案验证只在前台由页面触发，符合官方总则；无需该权限 |
| 自研 PatternLock 应用锁（华为架构指南 `custom_app_lock` 方案） | 需自管密钥与加解密，安全面远大于系统控件方案；本方案只做"看码门禁"，不做数据加密 |
| 服务卡片门禁 | 卡片不含验证码，无泄露面 |
| 按条目/按页面的差异化防截屏 | 官方 FAQ 明确全局与页面级混用会互相破坏；本方案只做全局 |
| 验证时机三档设置（v1） | 用 60 秒常量即可覆盖；后续加设置是纯增量（常量 + 1 个选择器） |
| 修改 `components/InfoCard.ets` | 被 `pages/index/Detail.ets` 与 `pages/user/Detail.ets` 共用，改动有回归风险；改为新增 `SettingCard.ets` |
