# 华为元服务「服务卡片 + 首屏信息密度」方案（MFA 元服务）

> **首次成文**：2026-10-02 ｜ **最近更新**：2026-10-04（对齐当前代码实现）
> **作者**：DeepSeek V4.1 Flash + yansongda
> **状态**：已实现并经人工审核确认
> **基线目录**：`huawei/atomicservice/MFA/`
>
> 本文档描述**当前**实现。历史里程碑（V2 迁移、卡片不刷新根因复盘、引导页简化等）见 §7；逐任务证据见 `docs/evidence/huawei-atomic-service-card-density/`。

## 0. 决策记录

| # | 决策 | 结论 |
|---|---|---|
| D1 | 卡片形态 | 不做卡内实时验证码（受系统刷新机制硬约束），改为**入口卡片**：账号数主视觉 + 「扫码添加 / 输入添加」两个快捷入口（卡内不取码） |
| D2 | 卡片数据 | 卡片不持有 TOTP secret，只读非敏感展示快照（仅账号数，不落任何账号明细） |
| D3 | 卡片尺寸 | 只做 `2*2`（卡片页按尺寸命名，为 `2*4` 预留）；`2*4` 列为候选 |
| D4 | 引导页 | 不做「首次展示 + 可关闭 + 持久化标记」；空态提示卡**无数据时固定展示** |
| D5 | 列表项 | 不加独立复制图标；**点击验证码数字区域即复制**，进度条形态保持不变 |
| D6 | 详情页 | 新增复制按钮；全局使用说明**收敛到「使用帮助」页**，详情页只留入口 |
| D7 | 「我的」页 | 新增统计（已保护 N 个账号）+「使用帮助」+「关于（版本号）」 |
| D8 | 后端 | 零后端改动；需后端的项列入 §8 候选 |
| D9 | 版本 | 按 `release-huawei-atomicservice` skill 发布 |

## 1. 背景与目标

**背景**：MFA 元服务提供 TOTP 两步验证 —— 扫码/手动输入添加 `otpauth` 条目，首页列表展示 6 位码 + 进度条，支持编辑/删除/拖拽排序，另有华为帐号登录页与「我的」页。改造前：无任何服务卡片（用户只有「打开应用」一条入口），首屏全屏引导 + 空态占满整屏（留白过多、可覆盖场景有限）。

**目标与约束**：

- **零后端改动**：所有能力端内闭环。
- **卡片必须在系统硬约束内**：卡片无法秒级刷新（定时刷新最小 30 分钟、每卡每日 50 次配额）、卡片渲染进程无网络/加密能力、`dataProxy` 等高级刷新对三方元服务不可用。
- **保持现有视觉识别**：列表项与详情页的进度条形态不变（无徽标、无秒数数字）。
- **可回滚**：卡片链路与首屏链路互不耦合，任一可独立回退。
- **不新增三方依赖**、**不改 `code-linter.json5`**。

## 2. 当前架构

### 2.1 目录结构（实际）

```
huawei/atomicservice/MFA/
├── module.json5                                     # extensionAbilities(form) + metadata(client_id/env)
├── resources/base/
│   ├── profile/form_config.json                     # 卡片配置（2*2，src 指向 pages/form/Form2x2.ets）
│   ├── profile/routes.json                          # NavDestination 路由（含 help）
│   ├── profile/pages.json                           # 仅 pages/Home
│   └── element/string.json                          # form_*（服务卡片）/ card_*（应用内卡片）/ index_* / user_* / help_* 文案
└── ets/
    ├── App.ets                                      # LogDomain / HttpDomain / AppEnv / AppPagesName / App
    ├── ability/
    │   ├── EntryAbility.ets                         # UIAbility：页面栈与主题初始化
    │   └── EntryFormAbility.ets                     # 服务卡片 FormExtensionAbility（独立进程）
    ├── models/
    │   ├── Auth.ets  User.ets                       # 登录态 / 用户配置（PersistenceV2）
    │   ├── form/FormBridge.ets                      # 卡片数据桥接（单一入口）
    │   ├── form/FormIntent.ets                      # 卡片意图（快捷入口路由）
    │   └── totp/{ItemRuntime,ItemsRuntime}.ets      # TOTP 条目运行时（端内算码 + 倒计时）
    ├── utils/
    │   ├── Form.ets                                  # 卡片展示快照读写（preferences，跨进程）
    │   ├── Clipboard.ets  Display.ets  Http.ets  Nav.ets  PromptAction.ets  Totp.ets
    ├── components/
    │   ├── InfoCard.ets  InputCard.ets  Header.ets  TotpCard.ets
    │   ├── IndexGuide.ets                           # 空态提示卡（纯展示）
    │   └── index/{AddFab,EmptyState,TotpListView}.ets
    ├── pages/
    │   ├── Home.ets  Login.ets  Help.ets            # Home 为 Navigation 容器（唯一 @Entry）
    │   ├── form/Form2x2.ets                          # 2*2 卡片 UI（不注册到 routes.json）
    │   ├── index/{Index,Detail,Create,EditText}.ets
    │   └── user/{Detail,Delete}.ets  user/edit/Slogan.ets
    ├── themes/Main.ets   types/Item.ets
```

> 注：原 `docs/huawei-atomic-service-card-density-agc.md`（AGC 提交材料）已于 2026-10-03 按需求删除。

### 2.2 链路总览

```
① 卡片数据下行（主应用 → 卡片刷新）
   Index.syncCards() ──▶ FormBridge.sync(ids) ──▶ Snapshot.write(count)
                                          └─▶ FormBridge.push() ──▶ formProvider.updateForm(formId)
   （卡片侧由系统在创建/定时刷新时经 EntryFormAbility.onAddForm / onUpdateForm 读快照装配）

② 卡片点击（快捷入口）
   整卡点击 ──▶ postCardAction(router, abilityName:'EntryAbility')  ──▶ 打开元服务首页（列表）
   「扫码添加」/「输入添加」──▶ postCardAction(router, params:{mfa_route:'scan'|'input'})
        ──▶ EntryAbility.onCreate / onNewWant ──▶ FormIntent(AppStorageV2).version++
        ──▶ Index @Monitor('formIntent.version') / onActive ──▶ addByScan() / pushPathByName('index/create')

③ 首屏（并行）
   无账号 ──▶ EmptyState（英雄区 + IndexGuide 固定提示卡 + 扫码/输入 + 帮助入口）
   有账号 ──▶ TotpListView（统计 + 排序 + 列表：点数字复制、左滑详情/删除）
```

### 2.3 进程模型

- **主应用进程**（`UIAbility`）：页面、`FormBridge`、`Clipboard`、端内算码。
- **卡片提供方进程**（`EntryFormAbility`）：独立进程、与主应用**共享文件沙箱**；只读 `preferences` 快照并装配 `formBindingData`，**不联网、不算码、不持有 secret**。
- **卡片渲染进程**：系统统一进程，与提供方内存隔离；数据只能以**字符串**经 `formBindingData` 注入。

## 3. 详细设计

### 3.1 服务卡片（2*2）

**卡片配置**（`resources/base/profile/form_config.json`，实际写入值）：

```json
{
  "forms": [
    {
      "name": "mfa_form",
      "displayName": "$string:form_display_name",
      "description": "$string:form_description",
      "src": "./ets/pages/form/Form2x2.ets",
      "uiSyntax": "arkts",
      "isDynamic": true,
      "isDefault": true,
      "defaultDimension": "2*2",
      "supportDimensions": ["2*2"],
      "updateEnabled": true,
      "updateDuration": 1,
      "formConfigAbility": "ability://EntryAbility",
      "dataProxyEnabled": false
    }
  ]
}
```

| 字段 | 取值 | 理由 |
|---|---|---|
| `supportDimensions` | `["2*2"]` | 元服务卡片尺寸固定不可缩放；每个声明尺寸都需出同尺寸快照素材，首版只做一个 |
| `updateDuration` | `1`（单位 30 分钟） | 兜底刷新；实时性由主应用主动 `updateForm` 负责 |
| `isDynamic` | `true` | 需要点击交互（`postCardAction`） |
| `dataProxyEnabled` | `false` | 代理刷新的数据提供方仅系统应用，三方元服务不可用 |
| `colorMode` | 不配置 | 已在 API 20 废弃，跟随系统 |

**卡片内容（2\*2）**：

```
┌──────────────────────┐  2*2 = 150×150vp，内容预算 ≈126×130vp
│  ▣ MFA认证            │   ← 品牌角标 Image + 标题
│  ─────────────────    │
│                      │
│         3            │   ← count（40fp 品牌色）与单位说明贴成一组
│     个账号已保护       │      整组在标题与入口之间居中
│ [扫码添加] [输入添加]   │   ← 两枚等宽入口（11fp，主 / 次）
└──────────────────────┘
        count == '0' 时  →  「还没有账号」+「点击添加第一个账号」在同一区间居中，入口行**保留**
```

UI 见 `pages/form/Form2x2.ets`：`@Entry @ComponentV2`，一个 `@Local`（`count`），`Title()` / `Filled()` / `Empty()` / `Actions()` 四个 `@Builder`；文本均 `maxLines(1)` + `textOverflow`；账号数区（`Filled()` / `Empty()`）带 `layoutWeight(1)` **吃掉标题与入口之间的剩余高度**——数字贴顶、单位说明贴底，把卡片撑满；`Actions()` 在**有账号与空态下都渲染**（空态正是最需要添加入口的时候）。空态由 `count == '0'` 推导，**不单独注入标记字段**。

**尺寸预算（2\*2）**：官方规格「小卡片 2\*2 = 150×150vp」（最小 132vp 宽），四周需留 12vp 安全边距，即**内容高度 ≈130vp、宽 ≈126vp**。当前排布在该预算内留有余量。**数字字号已接近 2\*2 的上限**（40fp）：账号数区（`layoutWeight(1)`）高度 ≈ 130 − 标题行 26 − 分割线 1 − 入口行 21 − 行距 9 ≈ 73vp，需同时容纳「数字行 + 说明行」（两组间不留额外内边距、整组居中）；再往上加会顶掉说明行或裁切入口行。若确需更大，只能牺牲标题行（可到约 50fp）。**新增卡片内容前必须先核对这个预算**：126vp 宽放不下两枚 5 字胶囊（12fp 需 128vp），故入口文字取 11fp、等宽均分。

**数据链路（快照）**：`utils/Form.ets` 的 `Snapshot` 类，preferences 库名 `mfa_form`。

```jsonc
// key: form_snapshot（示例值；只含账号数与时间戳）
{
  "count": 3,
  "updatedAt": 1790000000
}
```

主应用写入时机（均在 `pages/index/Index.ets` 既有分支上挂一行 `syncCards()`）：`refresh()` 成功后、`addByScan()` 成功后、删除成功后、`saveSort()` 成功后。

`Snapshot` 接口（**全部为同步方法**，首参 `context`）：

```ts
// utils/Form.ets
write(context, count: number)           // 落盘 form_snapshot：{ count, updatedAt }
read(context): SnapshotData             // JSON → { count, updatedAt }，异常回落空快照
addFormId(context, formId)              // 卡片添加时登记 formId（落盘 form_ids）
removeFormId(context, formId)           // 卡片移除时清除
listFormIds(context): string[]          // 供主动刷新遍历
// 内部：private prefs() / private parseFormIds()
```

**卡片数据注入约定**：卡片使用**状态管理 V2**，`updateForm` 注入的数据按**变量名**匹配卡片内 `@Local`，只注入字符串：

- `count`：账号数（数字字符串）。

对应常量在 `models/form/FormBridge.ets`：`FORM_FIELD_COUNT = 'count'`。**卡片侧文案一律用无参 `$r('app.string.form_*')`**，不使用带格式参数（`%d`/`%s`）的 `$r`（卡片渲染进程对带参格式化的支持未经证实），数量行用 `Text(this.count)` + `$r('app.string.form_protected_label')`（「个账号已保护」）拼接规避。

> **契约警示**：注入 key 必须与卡片 `@Local` 变量名逐字一致。写错/改名**不会编译报错，只会静默不刷新**，改一侧必须同步改另一侧。

**主动刷新链路**：主应用 `FormBridge.push()` 遍历 `Snapshot.listFormIds(context)` → `formProvider.updateForm(formId, data)`；失败仅记日志，不打断主流程。formId 在 `EntryFormAbility.onAddForm` 写入、`onRemoveForm` 清除。

**点击链路**：

- **整卡 / 「打开验证码」**：`postCardAction({action:'router', abilityName:'EntryAbility'})` —— 不携带参数，仅拉起元服务（冷启动落在首页列表）。
- **「添加账号」**：`postCardAction({action:'router', abilityName:'EntryAbility', params:{mfa_route:'add'}})` → `EntryAbility.onCreate/onNewWant` 解析（`FormIntent.fromWant`）→ `FormIntent`（AppStorageV2，`version++`）→ `Index` 的 `@Monitor('formIntent.version')` / `onActive` 消费 → `pushPathByName('index/create')`。意图**消费一次即清空**，避免重复跳转。

**边界（Must NOT）**：不做卡内按钮 message 事件、不做 `FormExtensionAbility` 算码、不放 secret、不做秒级刷新、不做 `dataProxy`。卡内交互一律走 `router` 事件（不用 `message` / `call`）。

### 3.2 首屏信息密度改造

| 位置 | 当前实现 | 保持不变 |
|---|---|---|
| `components/index/EmptyState.ets` | 英雄区（图标 + 「开始保护你的账号」+ 一句话价值说明）+ **固定展示**的提示卡 + 两个并列主按钮（扫码添加 / 手动输入）+ 次入口「查看使用帮助」 | 整屏垂直居中、超一屏可滚动 |
| `components/IndexGuide.ets` | **纯展示**提示卡：3 条价值要点（多设备同步 / 卡片直达 / 扫码添加）；**无「不再提示」、无关闭、无持久化标记** | 图标列定宽、文字左对齐 |
| `components/TotpCard.ets` | 验证码数字区域即复制入口（非排序态；点击右侧区域复制 + Toast） | issuer/username 排版、`code_font_size` 大字、`Progress` 形态（**无徽标、无秒数**） |
| `pages/index/Detail.ets` | 大字码下方「复制验证码」按钮 + 基本信息卡 + 配置信息卡 + 帮助入口卡 | `Progress` 形态、现有信息卡（**无秒数环**） |
| `pages/user/Detail.ets` | 头像（点击换）+ 统计行「已保护 N 个账号」+ 昵称/签名 + 个人信息（手机号，占位）+ 「更多」（使用帮助 / 关于（版本号）/ 注销账号） | 头像/昵称、现有「个人信息」入口 |
| `pages/Help.ets` | 静态使用帮助页：4 小节（添加账号 / 使用卡片 / 多设备同步 / 安全说明） | — |

> 行为变化：引导页不再记忆「已展示过 / 已关闭」。**只要没有账号就固定显示引导**；把账号删光后引导会重新出现。

**资源规范**：新字符串加在 `entry/src/main/resources/base/element/string.json`，前缀沿用 `index_index_page_*` / `index_detail_page_*` / `user_*` / `help_*` / `form_*`（**服务卡片专用**）/ `card_*`（页面内通用卡片，如 InfoCard / InputCard / TotpCard）；尺寸加在 `AppScope/resources/base/element/integer.json`。跨模块通用文案才放 `AppScope/resources/base/element/string.json`。

### 3.3 契约核对

| 契约 | 结论 | 状态 |
|---|---|---|
| 卡片配置文件字段、`supportDimensions` 取值、`updateDuration` 单位为 30 分钟 | OpenHarmony docs `arkts-ui-widget-configuration.md` | 已验证（外部官方源码） |
| 卡片渲染在系统统一进程，与提供方内存隔离；数据经 `formBindingData` 注入 | `arkts-ui-widget-process.md`、`arkts-ui-widget-interaction-overview.md` | 已验证（外部官方源码） |
| V2 卡片按**变量名**匹配注入数据，入口组件用裸 `@Entry`、不传 LocalStorage 实例；`@Local` 的「卡片能力」标注自 **API 23** 起 | 官方《卡片状态变量迁移》 | 已验证（官方文档） |
| `postCardAction` 支持 router/call/message；`call` 元服务暂不支持 | 官方文档 + 社区转述 | router 高 / call 限制 中 |
| 卡片刷新机制清单（定时 30min、`setFormNextRefreshTime` 最短 5min、`updateForm` 主动、`dataProxy` 仅系统应用） | 官方文档（被动刷新/页面刷新概述） | 已验证（外部官方源码） |
| `FormExtensionAbility` 独立进程、与主应用共享文件沙箱、创建后 10 秒无操作被清理 | `arkts-ui-widget-process.md`、`js-apis-app-form-formExtensionAbility.md` | 已验证（外部官方源码） |
| `FormExtensionAbility.onAddForm(want): formBindingData.FormBindingData` 为**同步**签名，`onUpdateForm`/`onRemoveForm` 返回 void | SDK `@ohos.app.form.FormExtensionAbility.d.ts:83/129/207` | 已验证（本机 SDK 源码） |
| `preferences` 同步 API（`getPreferencesSync`/`getSync`/`putSync`/`flushSync`）存在且带 `@atomicservice` | SDK `@ohos.data.preferences.d.ts:452/1114/1480/1743` | 已验证（本机 SDK 源码） |
| `formInfo.FormParam.IDENTITY_KEY = "ohos.extra.param.key.form_identity"`（卡片 formId 取值） | SDK `@ohos.app.form.formInfo.d.ts:679` | 已验证（本机 SDK 源码） |
| `$r('sys.symbol.X')` 名称必须在编译期符号表 `sysResource.js` 中存在 | SDK `ets/build-tools/ets-loader/sysResource.js` | 已验证（本机实测） |
| 卡片侧 `$r` 的**带参格式化**（`$r('app.string.x', arg)` / `%d`）支持 | 官方仅描述「卡片支持部分能力、接口带卡片能力标记」 | **未找到明确规定 → 设计规避（卡片只用无参 `$r` + 拼接）** |
| 卡片组件白名单是否在编译期强制 | **不强制**：`SymbolGlyph` 不在 `ets-loader/form_components/*.json` 白名单中却编译通过 | 已验证（本机实测）→ 卡内「能不能用某组件」只能靠**真机**判定 |
| preferences / pasteboard 的接口带 `@atomicservice` 标注（在元服务 API 集内） | SDK d.ts 标注（`preferences`/`pasteboard`/`formProvider`） | 接口归属已验证；运行时行为已真机实测（见 §7） |
| 主应用 `Totp.all()` 依赖登录态（`PersistenceV2` Authorization + Http 拦截器） | `utils/Http.ets`、`api/Totp.ets` | 已验证（读过源码） |
| 构建命令可用性 | `hvigorw.js assembleHap --mode module -p product=default --no-daemon` → `BUILD SUCCESSFUL` | 已验证（本机实测） |

## 4. 关键实现约束（易错点）

1. **跨进程 preferences 必须先清缓存再读**：主应用与卡片提供方是两个进程，`preferences` 实例按进程缓存在内存，某进程首次 `getPreferences` 后不再读持久化文件 → 看不到另一进程刚写入的值。`utils/Form.ets` 的 `Snapshot.prefs()` 已统一 `removePreferencesFromCacheSync` 后再 `getPreferencesSync`；**任何新增的跨进程 preferences 读写都必须复用该路径**。
2. **注入 key = 卡片 `@Local` 变量名**：编译期不可校验的隐性契约，两侧文件头均已注明。
3. **V2 与 V1 不可混用 / min API 23**：卡片为 `@Entry @ComponentV2`，`@LocalStorageProp` 等 V1 装饰器在其中编译报错；卡片 V2 接收能力由**设备系统版本**决定，故 `build-profile.json5` 的 `compatibleSdkVersion` 不得低于 `6.1.0(23)`。
4. **卡片组件白名单编译期不校验**：新增组件/属性一律以真机验证为准，优先复用已在卡片中跑通的组件。
5. **`onAddForm` 是同步签名**：卡片提供方侧读取快照、装配绑定数据必须全同步，无法 await 异步方法。
6. **preferences 不保证多进程并发安全**（官方只保证单进程安全）：当前数据量极小、写入频率极低，采用官方推荐的「清缓存读」作为读侧补偿。
7. **2\*2 卡片内容有硬尺寸预算**（≈126×130vp，见 §3.1「尺寸预算」）：新增元素前先核算；宁可减少内容也不要溢出——溢出会被卡片圆角裁切，且编译期不报错。

## 5. 风险与对策

| # | 风险 | 严重度 | 状态 / 对策 |
|---|---|---|---|
| R1 | preferences 在 `FormExtensionAbility` 不可用 → 卡片拿不到账号数据 | 高 | **已关闭**：文件沙箱共享，R1 证伪（见 §7） |
| R2 | `pasteboard` 在元服务页面不可用 → 列表/详情页复制不成立 | 高 | 真机 PoC 通过 |
| R4 | 卡片定时刷新有配额（50 次/日/卡），主动刷新依赖 formId 持久化 | 中 | formId 在 `onAddForm` 落 preferences、`onRemoveForm` 清除；仅数据真变更时 `updateForm` |
| R5 | 每声明一个尺寸需同尺寸快照素材，缺失导致 AGC 上传报错 | 中 | 只声明 `2*2`；快照素材与 AGC 说明人工出图 |
| R6 | 快照落盘明文账号信息，扩大暴露面 | 中 | **已消除**：快照只存 `count`/`updatedAt`，不落任何账号明细 |
| R7 | 首页 `Repeat + virtualScroll`、`swipeAction`、`onMove` 索引耦合，新增元素可能错位 | 中 | 新增元素一律放在 `List` **之外**，不动 `List` 内部结构 |
| R8 | 列表项复制区域点击同时触发「进详情」 | 低 | 复制区域独立 `onClick` 消费并判排序态 |
| R9 | 审核仍认为场景不足 | 中 | 回复附卡片截图/动图 + 首屏改版对比 + 候选清单 |
| R12 | 卡片侧 `$r` 带参格式化（`%d`）支持未证实 → 文案渲染异常 | 低 | 卡片侧只用无参 `$r`，数量行用拼接 |
| R13 | V2 卡片的数据接收（按变量名匹配）失败形态是静默不刷新 | 中 | **已实测可用**（负一屏每次可见重建卡片视图，创建时注入最新值） |
| R14 | min API 抬到 23 后 6.0.x/5.x 设备不可安装 | 中 | AGC 上架信息与版本说明需同步；如需保留老设备只能回退卡片到 V1 |
| R15 | 「注入 key = 卡片 `@Local` 变量名」是编译期不可校验的隐性契约 | 中 | 两侧文件头均已写明；改任一侧必须同步另一侧 |
| R16 | 卡内新增的 `Image` / `Divider` 属白名单内但无真机证据 | 低 | 真机验收确认；异常则先撤 `Image`，再撤 `Divider`（可分级回退） |
| R17 | 任何新增的跨进程 preferences 读写若忘记清缓存，会复现同类静默故障 | 中 | 已写入 `AGENTS.md` 约束，统一复用 `Snapshot.prefs()` |
| R18 | 卡片内子元素 `onClick` 与整卡 `onClick` 可能同时触发 → 动作重复 | 低 | 依赖 ArkUI「子组件 onClick 优先消费」；真机验证，若出现冒泡则给入口元素加 `hitTestBehavior(HitTestMode.Block)` |
| R19 | 卡内以 `Text` + 通用属性（背景色/圆角/onClick）充当按钮，未经真机验证 | 低 | 只复用卡片已跑通的 `Text` 与通用属性；真机确认渲染与点击均正常 |
| R20 | 卡片内容超出 2\*2 尺寸预算（≈126×130vp）会被圆角裁切，且**编译期不报错** | 中 | 新增内容前按 §3.1「尺寸预算」核算；必要时改走 2\*4（316×150vp） |

## 6. 监控与可观测性

复用现有 `hilog`（`LogDomain` 含 `FORM = 4`），不新增上报通道：

```jsonc
{"domain":4,"tag":"ability/EntryFormAbility","event":"onAddForm","formId":"…","count":3}
{"domain":4,"tag":"ability/EntryFormAbility","event":"onRemoveForm","formId":"…"}
```

| 指标 | 计算方式 | 关注阈值 |
|---|---|---|
| 快照读写失败率 | `utils/form` 异常日志次数 | > 0 即排查 |
| 卡片刷新失败率 | `updateForm` 失败日志次数 | > 0 即排查 |

## 7. 变更记录（里程碑）

| 时间 | 变更 |
|---|---|
| 2026-10-02 | 方案落地：卡片脚手架（`module.json5` + `form_config.json` + `EntryFormAbility` + `pages/form/FormCard.ets`）+ 首屏改造 + 列表/详情复制 + 「我的」页 + 帮助页 |
| 2026-10-03 | 删除 AGC 提交材料文档（按需求） |
| 2026-10-04 | **卡片状态管理 V2 迁移 + 展示重排**：`FormCard.ets` 由 `@Component` → `@ComponentV2`，3 个 `@LocalStorageProp` → 2 个 `@Local`（`count`/`first`），删除冗余字段 `hasItems`（空态由 `count == '0'` 推导）；`FormBridge` 引入 `FORM_FIELD_*` 常量；`SNAPSHOT_MAX_ITEMS` 2 → 1；`card_hint` 由「查看」改「复制」；min API 由 `6.0.0(20)` 抬到 `6.1.0(23)` |
| 2026-10-04 晚 | **复盘：卡片不刷新的真实根因是 preferences 跨进程缓存**。现象：加账号后卡片仍显示空态，「过一会儿重进负一屏」又正常。根因链：卡片添加时提供方写 formId → 主应用进程已缓存 `preferences` 实例、读不到 → `push()` 因 targets 为空直接 return → 从未 `updateForm`；应用被系统回收重启后实例重新从文件加载 → 读到 formId → 推送成功。**修复**：`Snapshot.prefs()` 先 `removePreferencesFromCacheSync` 再 `getPreferencesSync`，`write/read/addFormId/removeFormId/listFormIds` 全部改走它。R1 证伪、R13 降级为「已实测可用」 |
| 2026-10-04 | **重构与简化**：卡片快照模块 `utils/CardSnapshot.ets` → `utils/Card.ets`（类 `CardSnapshot` → `Snapshot`，`buildSnapshot` 收敛为私有静态方法 `Snapshot.build`，`CardSnapshotItem/Data` → `SnapshotItem/Data`）；引导页改为**无数据时固定展示**，删除 `models/Guide.ets`（`IndexGuideState`）与「不再提示」入口 |
| 2026-10-04 | **命名梳理（消除 Card 歧义）**：服务卡片族统一为 `Form*` —— `utils/Card.ets` → `utils/Form.ets`（类名保持 `Snapshot`）、`models/card/` → `models/form/`（`CardAction` → `FormAction`、`CardBridge` → `FormBridge`）、`pages/card/Card.ets` → `pages/form/FormCard.ets`、`CARD_FIELD_*` → `FORM_FIELD_*`；页面内通用卡片组件 `components/Card.ets` → `components/InfoCard.ets`（`Card`/`CardItem` → `InfoCard`/`InfoCardItem`）、`components/CardInput.ets` → `components/InputCard.ets` |
| 2026-10-04 | **卡片交互简化**：2*2 卡片去掉「点卡复制验证码」，改为只展示「标题 / X 个账号 / 打开查看验证码」三行（**去掉 issuer 展示**），整卡点击仅打开元服务首页；随之移除失效的复制链路（`FormAction`、`EntryAbility` 的 want 处理、`Index` 的 `formAction`/`consumeFormAction`/`@Monitor`、`FORM_FIELD_FIRST`），快照简化为只存 `count`/`updatedAt`（**顺带关闭 R6**）；卡片页 `FormCard.ets` → `FormCard2x2.ets`（struct 同名，为 2*4 预留） |
| 2026-10-04 | **卡片充实（方案 A+C）**：2×2 卡片改为「账号数主视觉（36fp）+ 状态小字」加「打开验证码 / 添加账号」双入口，主内容块上下各一个 `Blank()` 垂直居中；新增 `models/form/FormIntent.ets`（意图路由）支持「添加账号」直达 `index/create`，`EntryAbility` 恢复 `onCreate`/`onNewWant` 解析 `mfa_route`；文案 `card_count_suffix`/`card_hint` 替换为 `card_protected_label`/`card_status_hint`/`card_action_open`/`card_action_add`，新增尺寸 `card_number_font_size` |
| 2026-10-04 | **修正 2\*2 内容溢出**：原布局（20fp 标题 + 36fp 数字 + 状态小字 + 10vp 行距 + 两枚 12fp 胶囊）约 167vp，超出 2\*2 预算。按官方规格重排——大数字 36fp→28fp 并与单位说明同行、去掉状态小字、列间距 10vp→6vp、入口文字 12fp→11fp 等宽均分；新增 `card_action_font_size`（11fp），移除 `card_status_hint` |
| 2026-10-04 | **卡片入口改为添加流程**：底部两枚入口由「打开验证码 / 添加账号」改为「**扫码添加 / 输入添加**」（`card_action_scan` / `card_action_input`），各带 `mfa_route`（`scan` / `input`）直达扫码或手动输入；账号数改为**两行居中**（`1` 独占一行、`个账号已保护` 独占一行），数字 28fp→24fp；`Actions()` 改为**空态也保留** |
| 2026-10-04 | **卡片排版撑满**：账号数区改为 `layoutWeight(1)` 吃掉剩余高度——数字 24fp→**30fp** 并贴顶（区顶 `padding-top: 6vp`）、单位说明 12fp→**11fp**（新增 `card_label_font_size`）并贴底（区内 `Blank()` 撑开）；列间距 5vp→4vp |
| 2026-10-04 | **数字加大**：`card_number_font_size` 30fp→**38fp**（接近 2\*2 上限，推导见 §3.1「尺寸预算」）；行距 4vp→3vp、账号数区顶部内边距 6vp→4vp，把空间让给数字，消除数字与说明之间的空洞 |
| 2026-10-05 | **卡片排版改为「成组居中」**：数字与单位说明贴成一组、整组在标题与入口之间居中（去掉原「数字贴顶、说明贴底」写法与数字区顶部内边距）；数字 38fp→**40fp**；入口胶囊内边距 4vp→3vp 让出高度；`Filled()` 与 `Empty()` 形态统一（同为 `layoutWeight(1)` + `justifyContent(Center)`） |
| 2026-10-05 | **命名对齐：服务卡片族残留的 `card_*` 全部收敛为 `form_*`**。① `form_config.json`：卡片名 `mfa_card` → `mfa_form`、`src` → `pages/form/Form2x2.ets`；② `string.json` 10 条：`card_ability_label`/`card_ability_desc`/`card_display_name`/`card_description`/`card_title`/`card_protected_label`/`card_empty_title`/`card_empty_hint`/`card_action_scan`/`card_action_input` → `form_*`（文案值不变）；③ `float.json` 3 条：`card_number_font_size`/`card_label_font_size`/`card_action_font_size` → `form_*`；④ 卡片页 `pages/form/FormCard2x2.ets` → `Form2x2.ets`（struct 同名）；⑤ `utils/Form.ets`：preferences 库名 `mfa_card` → `mfa_form`、key `card_snapshot` → `form_snapshot`、`card_form_ids` → `form_ids`。**注意**：卡片名与 preferences 库名变更后，设备上已添加的卡片需**重新添加**（旧 formId 与新库名均不再生效）；应用内通用卡片命名（`card_radius`/`card_height` 等 integer、InfoCard/InputCard/TotpCard 及其文案）**刻意不动**，避免与服务卡片语义混淆 |

## 8. 附录：本次不做、候选清单

| 项 | 是否需后端 | 说明 |
|---|---|---|
| 卡片内取码（`message` 事件 + 提供方算码 + 剪贴板），或 2×4 逐行点击复制 | 否 | 前者需评估 secret 共享的安全代价；后者只需 `postCardAction` 带 `mfa_item_id`，成本较低 |
| 「卡片实时显示验证码」 | 否 | **当前系统机制下不可实现**（无秒级刷新） |
| `2*4` 卡片规格 | 否 | 第二套布局 + 快照素材；卡片页已按尺寸命名（`Form2x2.ets`），新增即 `Form2x4.ets` |
| 批量导入（相册选图识别二维码，`ScanKit`） | 否 | 价值高，端内可取 |
| 搜索与分组（条目 > 10 时出现） | 否 | 端内可取 |
| 应用锁（生物识别） | 否 | 需核实元服务 API 集 |
| 加密备份/恢复（导出 otpauth 批量文本） | 否（需 picker/share 能力核实） | 端内可行则不需要后端 |
| 云端备份版本历史、跨端同步状态查询 | **是** | 需 `application-rs` 增加接口 |
| 意图框架 / 搜索直达接入 | 否（需 AGC 配置） | 需元服务侧配置与联调 |
| `2in1` 等多设备适配 | 否 | `deviceTypes` + UI 双端适配成本 |

## 9. 相关文档与证据

- 工程约束：`huawei/atomicservice/MFA/AGENTS.md`
- 逐任务证据与实测截图：`docs/evidence/huawei-atomic-service-card-density/`
- 端内算码方案：`docs/huawei-totp-local-compute.md`
