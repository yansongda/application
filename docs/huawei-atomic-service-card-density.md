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
| D1 | 卡片形态 | 不做卡内实时验证码（受系统刷新机制硬约束），改为**清单型入口卡片 + 点击直达即复制** |
| D2 | 卡片数据 | 卡片不持有 TOTP secret，只读非敏感展示快照（账号数 / 首个 issuer） |
| D3 | 卡片尺寸 | 只做 `2*2`；`2*4` 列为候选 |
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
│   ├── profile/form_config.json                     # 卡片配置（2*2，src 指向 pages/form/FormCard.ets）
│   ├── profile/routes.json                          # NavDestination 路由（含 help）
│   ├── profile/pages.json                           # 仅 pages/Home
│   └── element/string.json                          # card_* / index_* / user_* / help_* 文案
└── ets/
    ├── App.ets                                      # LogDomain / HttpDomain / AppEnv / AppPagesName / App
    ├── ability/
    │   ├── EntryAbility.ets                         # UIAbility：卡片动作解析、页面栈与主题初始化
    │   └── EntryFormAbility.ets                     # 服务卡片 FormExtensionAbility（独立进程）
    ├── models/
    │   ├── Auth.ets  User.ets                       # 登录态 / 用户配置（PersistenceV2）
    │   ├── form/FormAction.ets                      # 卡片待办动作（AppStorageV2）
    │   ├── form/FormBridge.ets                      # 卡片数据桥接（单一入口）
    │   └── totp/{ItemRuntime,ItemsRuntime}.ets      # TOTP 条目运行时（端内算码 + 倒计时）
    ├── utils/
    │   ├── FormForm.ets                                 # 卡片展示快照读写（preferences，跨进程）
    │   ├── Clipboard.ets  Display.ets  Http.ets  Nav.ets  PromptAction.ets  Totp.ets
    ├── components/
    │   ├── InfoCard.ets  InputCard.ets  Header.ets  TotpCard.ets
    │   ├── IndexGuide.ets                           # 空态提示卡（纯展示）
    │   └── index/{AddFab,EmptyState,TotpListView}.ets
    ├── pages/
    │   ├── Home.ets  Login.ets  Help.ets            # Home 为 Navigation 容器（唯一 @Entry）
    │   ├── card/Card.ets                            # 卡片 UI（不注册到 routes.json）
    │   ├── index/{Index,Detail,Create,EditText}.ets
    │   └── user/{Detail,Delete}.ets  user/edit/Slogan.ets
    ├── themes/Main.ets   types/Item.ets
```

> 注：原 `docs/huawei-atomic-service-card-density-agc.md`（AGC 提交材料）已于 2026-10-03 按需求删除。

### 2.2 链路总览

```
① 卡片数据下行（主应用 → 卡片刷新）
   Index.syncCards() ──▶ FormBridge.sync() ──▶ Snapshot.write(preferences: mfa_card)
                                          └─▶ FormBridge.push() ──▶ formProvider.updateForm(formId)
   （卡片侧由系统在创建/定时刷新时经 EntryFormAbility.onAddForm / onUpdateForm 读快照装配）

② 卡片点击上行（点卡即复制）
   卡片整卡 onClick ──▶ postCardAction(router, {mfa_action:'copy'})
        ──▶ EntryAbility.onCreate / onNewWant ──▶ FormAction(AppStorageV2).version++
        ──▶ Index @Monitor('formAction.version') / onActive / refresh 锚点 ──▶ consumeFormAction()
        ──▶ ItemRuntime.freshCode()（端内算码，secret 缺失回落 Totp.detail）──▶ Clipboard.copy() + Toast

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
      "name": "mfa_card",
      "displayName": "$string:card_display_name",
      "description": "$string:card_description",
      "src": "./ets/pages/form/FormCard.ets",
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
┌──────────────────────┐
│  ▣ MFA认证            │   ← 品牌角标 Image + 标题
│  ─────────────────    │
│  3 个账号             │   ← count（品牌色加粗）+ 后缀
│  GitHub              │   ← first（首个 issuer，单行省略）
│  点击复制验证码        │   ← 底部提示语
└──────────────────────┘
        count == '0' 时  →  「还没有账号」+「点击添加第一个账号」
```

UI 见 `pages/form/FormCard.ets`：`@Entry @ComponentV2`，两个 `@Local`（`count` / `first`），`Title()` / `Filled()` / `Empty()` 三个 `@Builder`；标题与首个 issuer 均 `maxLines(1)` + `textOverflow`，`Blank()` 撑底使提示语贴底。空态由 `count == '0'` 推导，**不单独注入标记字段**。

**数据链路（快照）**：`utils/Form.ets` 的 `Snapshot` 类，preferences 库名 `mfa_card`。

```jsonc
// key: card_snapshot（示例值；不含 secret、不含验证码）
{
  "count": 3,
  "updatedAt": 1790000000,
  "items": [
    { "id": "0192…", "issuer": "GitHub", "username": "me@x.com" }
  ]
}
```

主应用写入时机（均在 `pages/index/Index.ets` 既有分支上挂一行 `syncCards()`）：`refresh()` 成功后、`addByScan()` 成功后、删除成功后、`saveSort()` 成功后。

`Snapshot` 接口（**全部为同步方法**，首参 `context`）：

```ts
// utils/Form.ets
write(context, items: SnapshotItem[])   // 落盘 card_snapshot，items 截断为前 1 条
read(context): SnapshotData             // JSON → { count, updatedAt, items[] }，异常回落空快照
addFormId(context, formId)              // 卡片添加时登记 formId
removeFormId(context, formId)           // 卡片移除时清除
listFormIds(context): string[]          // 供主动刷新遍历
// 内部：private prefs() / private parseFormIds() / private build()
```

**卡片数据注入约定**：卡片使用**状态管理 V2**，`updateForm` 注入的数据按**变量名**匹配卡片内 `@Local`，只注入字符串：

- `count`：账号数（数字字符串）；
- `first`：首个 issuer（空态为 `''`）。

对应常量在 `models/form/FormBridge.ets`：`FORM_FIELD_COUNT = 'count'`、`FORM_FIELD_FIRST = 'first'`。**卡片侧文案一律用无参 `$r('app.string.card_*')`**，不使用带格式参数（`%d`/`%s`）的 `$r`（卡片渲染进程对带参格式化的支持未经证实），数量行用 `Text(this.count)` + `$r('app.string.card_count_suffix')`（「个账号」）拼接规避。

> **契约警示**：注入 key 必须与卡片 `@Local` 变量名逐字一致。写错/改名**不会编译报错，只会静默不刷新**，改一侧必须同步改另一侧。

**主动刷新链路**：主应用 `FormBridge.push()` 遍历 `Snapshot.listFormIds(context)` → `formProvider.updateForm(formId, data)`；失败仅记日志，不打断主流程。formId 在 `EntryFormAbility.onAddForm` 写入、`onRemoveForm` 清除。

**拉起链路**：卡片整卡 `postCardAction({action:'router', abilityName:'EntryAbility', params:{mfa_action:'copy'}})` → `EntryAbility.onCreate/onNewWant` 解析（`FormAction.fromWant`）→ `models/form/FormAction`（AppStorageV2，`version++`）→ `Index` 消费 → `ItemRuntime.freshCode()` 端内算码（`secret` 缺失时回落 `Totp.detail(id)`）→ `Clipboard.copy()` → Toast「验证码已复制」。

**关键契约与消费语义**：

- **want 参数是 JSON 字符串**：`postCardAction` 的 `params` 被整体包装为 `want.parameters.params`（string），卡片侧 `params` **不逐键平铺**；解析须 `JSON.parse(want.parameters.params as string)` 后取 `mfa_action`。
- **消费互斥**：`Index` 内用 `isConsuming` 互斥标志，避免 `@Monitor` 与 `onActive` 双路径并发消费。
- **失败不清空**：仅**复制成功**后清空 `FormAction`；失败保留待办（「无论成败都清空」会把一次瞬时失败变成永久失败）。
- **待办重试锚点**：在 `refresh()` 的 `finally`（`isFetching = false` 之后）重试消费待办 —— 关闭「热启动时页面未重新激活、且该次 refresh 被 `isFetching` 去重静默返回」导致待办永不消费的时序漏洞。
- **失败与永挂边界**：`refresh()` 失败会 reject，故消费内部必须 try/catch 且各调用点 `.catch()`；`refresh()` 成功但账号数仍为 0 → 清空待办（避免日后添加首个账号时意外自动复制）。
- **空列表点卡**：`ids` 为空时不做复制，只静默进入列表（首屏已可见添加入口），不弹「复制失败」。
- **监听必须用状态装饰器**：`@Monitor('formAction.version')` 的目标变量须为 `@Local`，否则监听不到变化。

**边界（Must NOT）**：不做卡内按钮 message 事件、不做 `FormExtensionAbility` 算码、不放 secret、不做秒级刷新、不做 `dataProxy`、不做 `2*4`。

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

**资源规范**：新字符串加在 `entry/src/main/resources/base/element/string.json`，前缀沿用 `index_index_page_*` / `index_detail_page_*` / `user_*` / `help_*` / `card_*`；尺寸加在 `AppScope/resources/base/element/integer.json`。跨模块通用文案才放 `AppScope/resources/base/element/string.json`。

### 3.3 契约核对

| 契约 | 结论 | 状态 |
|---|---|---|
| 卡片配置文件字段、`supportDimensions` 取值、`updateDuration` 单位为 30 分钟 | OpenHarmony docs `arkts-ui-widget-configuration.md` | 已验证（外部官方源码） |
| 卡片渲染在系统统一进程，与提供方内存隔离；数据经 `formBindingData` 注入 | `arkts-ui-widget-process.md`、`arkts-ui-widget-interaction-overview.md` | 已验证（外部官方源码） |
| V2 卡片按**变量名**匹配注入数据，入口组件用裸 `@Entry`、不传 LocalStorage 实例；`@Local` 的「卡片能力」标注自 **API 23** 起 | 官方《卡片状态变量迁移》 | 已验证（官方文档） |
| `postCardAction` 支持 router/call/message；`call` 元服务暂不支持 | 官方文档 + 社区转述 | router 高 / call 限制 中 |
| 卡片刷新机制清单（定时 30min、`setFormNextRefreshTime` 最短 5min、`updateForm` 主动、`dataProxy` 仅系统应用） | 官方文档（被动刷新/页面刷新概述） | 已验证（外部官方源码） |
| `FormExtensionAbility` 独立进程、与主应用共享文件沙箱、创建后 10 秒无操作被清理 | `arkts-ui-widget-process.md`、`js-apis-app-form-formExtensionAbility.md` | 已验证（外部官方源码） |
| `postCardAction` 的 `params` 经 `want.parameters.params`（JSON **字符串**）传递，需 `JSON.parse` 后取值 | `arkts-ui-widget-event-router.md:110-123` | 已验证（外部官方源码） |
| `@Monitor` 目标变量必须被 `@Local`/`@Param`/`@Provider`/`@Consumer`/`@Computed` 装饰 | `arkts-new-monitor.md:28,156` | 已验证（外部官方源码） |
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

## 5. 风险与对策

| # | 风险 | 严重度 | 状态 / 对策 |
|---|---|---|---|
| R1 | preferences 在 `FormExtensionAbility` 不可用 → 卡片拿不到账号数据 | 高 | **已关闭**：文件沙箱共享，R1 证伪（见 §7） |
| R2 | `pasteboard` 在元服务页面不可用 → 「点卡片即复制」不成立 | 高 | 真机 PoC 通过；降级方案为「点卡片直达详情页」 |
| R3 | router 事件拉起后 want 参数缺失/格式不符 | 中 | `onCreate`（冷启动）与 `onNewWant`（热启动）两路都实现；参数缺失时静默进列表 |
| R4 | 卡片定时刷新有配额（50 次/日/卡），主动刷新依赖 formId 持久化 | 中 | formId 在 `onAddForm` 落 preferences、`onRemoveForm` 清除；仅数据真变更时 `updateForm` |
| R5 | 每声明一个尺寸需同尺寸快照素材，缺失导致 AGC 上传报错 | 中 | 只声明 `2*2`；快照素材与 AGC 说明人工出图 |
| R6 | 快照把 issuer/username 明文写入 preferences，扩大暴露面 | 中 | 只存展示字段（无 secret、无验证码），代码注释与本文档标注该取舍 |
| R7 | 首页 `Repeat + virtualScroll`、`swipeAction`、`onMove` 索引耦合，新增元素可能错位 | 中 | 新增元素一律放在 `List` **之外**，不动 `List` 内部结构 |
| R8 | 列表项复制区域点击同时触发「进详情」 | 低 | 复制区域独立 `onClick` 消费并判排序态 |
| R9 | 审核仍认为场景不足 | 中 | 回复附卡片截图/动图 + 首屏改版对比 + 候选清单 |
| R10 | 卡片动作被双路径并发消费 → 重复复制/Toast 叠显，或一次瞬时失败后待办被清空 | 中 | `isConsuming` 互斥 + 列表未就绪时不消费 + **仅成功后清空**；空列表点卡静默引导 |
| R11 | want 参数格式理解错误（误按平铺取值）导致取不到参数 | 中 | 按官方契约 `JSON.parse(want.parameters.params)`；区分「参数缺失」与「解析/键名错误」 |
| R12 | 卡片侧 `$r` 带参格式化（`%d`）支持未证实 → 文案渲染异常 | 低 | 卡片侧只用无参 `$r`，数量行用拼接 |
| R13 | V2 卡片的数据接收（按变量名匹配）失败形态是静默不刷新 | 中 | **已实测可用**（负一屏每次可见重建卡片视图，创建时注入最新值） |
| R14 | min API 抬到 23 后 6.0.x/5.x 设备不可安装 | 中 | AGC 上架信息与版本说明需同步；如需保留老设备只能回退卡片到 V1 |
| R15 | 「注入 key = 卡片 `@Local` 变量名」是编译期不可校验的隐性契约 | 中 | 两侧文件头均已写明；改任一侧必须同步另一侧 |
| R16 | 卡内新增的 `Image` / `Divider` 属白名单内但无真机证据 | 低 | 真机验收确认；异常则先撤 `Image`，再撤 `Divider`（可分级回退） |
| R17 | 任何新增的跨进程 preferences 读写若忘记清缓存，会复现同类静默故障 | 中 | 已写入 `AGENTS.md` 约束，统一复用 `Snapshot.prefs()` |

## 6. 监控与可观测性

复用现有 `hilog`（`LogDomain` 含 `FORM = 4`），不新增上报通道：

```jsonc
{"domain":4,"tag":"ability/EntryFormAbility","event":"onAddForm","formId":"…","count":3}
{"domain":4,"tag":"ability/EntryFormAbility","event":"onRemoveForm","formId":"…"}
{"domain":3,"tag":"pages/index","event":"formAction","action":"copy","result":"success|fail"}
```

| 指标 | 计算方式 | 关注阈值 |
|---|---|---|
| 卡片动作消费成功率 | `result=success` / `action=copy` 总数 | 真机验收期要求 100% |
| 快照读写失败率 | `utils/form-snapshot` 异常日志次数 | > 0 即排查 |
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

## 8. 附录：本次不做、候选清单

| 项 | 是否需后端 | 说明 |
|---|---|---|
| 卡片内「复制验证码」按钮（message 事件 + 提供方算码 + 剪贴板） | 否 | 需评估 secret 共享的安全代价，PoC 通过后单独评估 |
| 「卡片实时显示验证码」 | 否 | **当前系统机制下不可实现**（无秒级刷新） |
| `2*4` 卡片规格 | 否 | 第二套布局 + 快照素材 |
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
