# 华为元服务「服务卡片 + 首屏信息密度」改造方案（MFA 元服务）

> **时间**：2026-10-02
> **作者**：DeepSeek V4.1 Flash + yansongda
> **状态**：经过人工审核确认

## 0. 决策记录（已确认）

| # | 决策 | 结论 |
|---|---|---|
| D1 | 卡片形态 | 不做卡内实时验证码（受系统刷新机制硬约束），改为**清单型入口卡片 + 点击直达即复制** |
| D2 | 卡片数据 | 卡片不持有 TOTP secret，只读非敏感展示快照（账号数 / issuer / username） |
| D3 | 卡片尺寸 | 首版只做 `2*2`；`2*4` 列为下版本候选 |
| D4 | 引导页 | 4 屏全屏 Swiper → 首页内嵌单屏说明块（可关闭，沿用 `IndexGuideState.isSkipped`） |
| D5 | 列表项 | 仅新增复制按钮；**不加圆形徽标、不加剩余秒数数字，进度条形态保持不变** |
| D6 | 详情页 | 仅新增复制按钮 + 使用说明卡；**不加剩余秒数环，保持现有 Progress 形态** |
| D7 | 「我的」页 | 新增统计（已保护 N 个账号）+「使用帮助」+「关于（版本号）」 |
| D8 | 后端 | 本次零后端改动；需后端的项列入附录候选 |
| D9 | 版本 | 完成后按 `release-huawei-atomicservice` skill 发 1.5.0（本文档不含版本号与 CHANGELOG 改动） |

## 1. 背景与问题

**现状**（均已读源码验证）：华为元服务「MFA认证」v1.4.0 提供 TOTP 两步验证码 —— 扫码/手动输入添加 `otpauth` 条目，首页列表展示 6 位码 + 进度条，支持编辑/删除/拖拽排序，另有华为帐号登录页与「我的」页。工程内**没有任何服务卡片**（`entry/src/main/module.json5` 无 `extensionAbilities`，全工程 grep `form`/`widget`/`form_config` 零命中）。

**困境**（华为审核反馈「留白过多 + 可覆盖的使用场景有限」拆解为 4 条）：

1. **首屏无内容**：首次进入是全屏 4 步引导（`components/IndexGuide.ets`，一屏一个 `guide_icon_font_size: 100fp` 图标 + 一行标题），`IndexGuideState.isSkipped` 持久化后改为展示 `pages/index/Index.ets:172` 的 `empty()`（图标 + 「暂无数据」占满整屏）。
2. **信息密度低**：列表项仅 issuer / username / 6 位码 / 进度条 4 类信息且无任何操作（`components/TotpCard.ets`，`card_height: 100`）；详情页仅 3 个字段（`pages/index/Detail.ets:19-57`）；「我的」页仅头像 + 昵称 + 1 个入口（`pages/user/Index.ets:18-34`）。
3. **缺元服务核心形态**：无服务卡片，用户只有"打开应用"一条入口路径。
4. **无系统级入口**：无意图接入、无搜索直达、无快捷方式。

**目标**（约束条件）：

- **零后端改动**：所有能力端内闭环
- **保持现有视觉识别**：列表项与详情页的进度条形态、无徽标、无秒数数字（见 D5/D6）
- **卡片必须在系统硬约束内**：卡片无法秒级刷新（定时刷新最小 30 分钟、每卡每日 50 次配额）、卡片渲染进程无网络/加密能力、`dataProxy` 等高级刷新对三方元服务不可用
- **可回滚**：卡片链路与首屏链路互不耦合，任一可独立回退
- **不新增三方依赖**、**不改 `code-linter.json5`**

## 2. 整体方案

**核心思路**：**把元服务从"打开才能用的工具"变成"桌面卡片直达的服务"，同时把首屏从"空白引导"改成"首屏即功能"。**

```
                    ┌──────────────────────────────┐
   桌面服务卡片 ────▶│ 卡片展示：账号数 + 首个账号名   │ ← FormExtensionAbility 读 preferences 快照
   (2*2)            │ 点击整卡 → router 事件         │
                    └──────────┬───────────────────┘
                               │ want.parameters.params = '{"mfa_action":"copy"}'（JSON 字符串，需 JSON.parse）
                               ▼
   ┌─────────────────────────────────────────────────────────┐
   │ EntryAbility.onCreate / onNewWant → models/CardAction 落内存态 │
   └──────────┬──────────────────────────────────────────────┘
              ▼
   ┌─────────────────────────────────────────────────────────┐
   │ Index.onActive → refresh() 完成后消费动作 → 端内算码        │
   │                → utils/Clipboard 写剪贴板 → Toast「已复制」  │
   └─────────────────────────────────────────────────────────┘

   主应用数据变更(refresh/add/delete/sort) ──▶ utils/CardSnapshot 写 preferences
                                          └─▶ formProvider.updateForm() 主动刷新卡片

   首屏改造（并行）：空态 → 首屏即功能 ｜ 引导页 → 内嵌一次 ｜ 列表/详情/我的 → 补齐操作与说明
```

**文件结构变更**（基线目录：`huawei/atomicservice/MFA/`）：

```
entry/src/main/
├── module.json5                                     [改] + extensionAbilities(form) 段
├── resources/base/
│   ├── profile/form_config.json                     [新] 卡片配置（2*2）
│   ├── profile/routes.json                          [改] + user/help 路由
│   └── element/string.json                          [改] + card_* / index_* / user_* 文案
└── ets/
    ├── entryformability/EntryFormAbility.ets        [新] 卡片生命周期 + 数据装配 + formId 持久化
    ├── card/pages/Card.ets                          [新] 卡片 UI（2*2）
    ├── ability/EntryAbility.ets                     [改] + onCreate/onNewWant 解析 want
    ├── models/CardAction.ets                        [新] 卡片待办动作（AppStorageV2 内存态）
    ├── utils/Clipboard.ets                          [新] 剪贴板封装（页面/卡片动作共用）
    ├── utils/CardSnapshot.ets                       [新] preferences 快照读写（含 formId 读写）
    ├── App.ets                                      [改] LogDomain + FORM = 4、AppPagesName + USER_HELP
    ├── pages/index/Index.ets                        [改] 空态重构 + 引导内嵌 + 快照写入 + 动作消费
    ├── components/IndexGuide.ets                    [改] Swiper → 内嵌说明块
    ├── components/TotpCard.ets                      [改] + 复制按钮
    ├── pages/index/Detail.ets                       [改] + 复制按钮 + 使用说明卡
    ├── pages/user/Index.ets                         [改] + 统计 / 使用帮助 / 关于
    └── pages/user/Help.ets                          [新] 使用帮助静态页

AppScope/resources/base/element/integer.json         [改] + action_icon_size
docs/evidence/huawei-atomic-service-card-density/    [新] 逐任务证据
```

> 注：原 `docs/huawei-atomic-service-card-density-agc.md`（AGC 提交与审核回复材料）已于 2026-10-03 按需求删除。

## 3. 详细设计

### 3.1 服务卡片（P0-1）

**卡片配置**（`resources/base/profile/form_config.json`，实际写入值）：

```json
{
  "forms": [
    {
      "name": "mfa_card",
      "displayName": "$string:card_display_name",
      "description": "$string:card_description",
      "src": "./ets/card/pages/Card.ets",
      "uiSyntax": "arkts",
      "isDynamic": true,
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
| `supportDimensions` | `["2*2"]` | 元服务卡片尺寸固定不可缩放（中置信度）；每个声明尺寸都需出同尺寸快照素材，首版只做一个 |
| `updateDuration` | `1`（单位 30 分钟） | 兜底刷新；实时性由主应用主动 `updateForm` 负责 |
| `isDynamic` | `true` | 需要点击交互（`postCardAction`） |
| `dataProxyEnabled` | `false` | 代理刷新的数据提供方仅系统应用，三方元服务不可用 |
| `colorMode` | 不配置 | 已在 API 20 废弃，跟随系统 |

**卡片内容（2\*2）**：

```
┌──────────────────────┐
│  MFA认证              │
│                      │
│  3 个账号             │
│  GitHub              │
│  点击查看验证码        │
└──────────────────────┘
        count = 0 时  →  「还没有账号 / 点击添加第一个账号」
```

**数据链路（快照）**：

```json
// preferences key: card_snapshot（示例值；不含 secret、不含验证码）
{
  "count": 3,
  "updatedAt": 1790000000,
  "items": [
    { "id": "0192…", "issuer": "GitHub", "username": "me@x.com" },
    { "id": "0192…", "issuer": "华为云", "username": "yansongda" }
  ]
}
```

主应用写入时机（均在 `pages/index/Index.ets` 既有分支上挂一行）：`refresh()` 成功后、`addByScan()` 成功后、删除成功后、`saveSort()` 成功后。

**卡片数据注入约定**（跨进程数据只能以字符串传递）：`FormExtensionAbility` 注入字符串 key —— `count`（数字字符串）、`first`（首个 issuer）。**卡片侧文案一律用无参 `$r('app.string.card_*')` 渲染，不使用带格式参数（`%d`/`%s`）的 `$r`**——卡片渲染进程对带参格式化的支持未经核实（官方文档仅有「支持部分组件/事件/动效/数据管理能力、接口带‘卡片能力’标记」的描述），因此数量行用 `Text(this.count)` + `$r('app.string.card_count_suffix')`（“个账号”）拼接规避；空态由 `count == '0'` 推导，渲染 `card_empty_title` + `card_empty_hint`。提供方是非 UI 上下文，**不得**在其中调用 `$r`。

> ⚠️ 2026-10-04 变更：原设计注入第 3 个 key `hasItems`、卡片侧用 `@LocalStorageProp` 接收；现已改为**状态管理 V2**（卡片按变量名匹配，仅注入 `count` / `first`，`hasItems` 作为冗余字段删除）。以 **§8 变更记录** 为准，本节其余内容仍有效。

伪代码：
```
// utils/CardSnapshot.ets（全部同步方法，首参 context）
write(context, items): prefs.put('card_snapshot', json(buildSnapshot(items)))   // buildSnapshot 截断前 1 条（2026-10-04 起）
read(context):        json → { count, items[] } | 空快照兜底
addFormId(context, formId) / removeFormId(context, formId) / listFormIds(context): string[]   // 供主动刷新
```

**主动刷新链路**：主应用侧遍历 `CardSnapshot.listFormIds(context)` → `formProvider.updateForm(formId, data)`；formId 在 `EntryFormAbility.onAddForm` 写入、`onRemoveForm` 清除。（`CardSnapshot` 全部为同步方法：`onAddForm` 是同步签名，异步方法无法在其内 `await`。）

**拉起链路**：卡片整卡 `postCardAction({action:'router', abilityName:'EntryAbility', params:{mfa_action:'copy', mfa_item_id}})` → `EntryAbility.onCreate/onNewWant` 解析 → `models/CardAction`（AppStorageV2）→ `Index` 消费 → `TotpCode.compute()` 端内算码（`secret` 缺失时回落 `Totp.detail(id)`）→ `Clipboard.copy()` → Toast「验证码已复制」；任一环节失败不阻断，静默停留在列表页。

关键契约与消费语义：

- **want 参数是 JSON 字符串**：`postCardAction` 的 `params` 被整体包装为 `want.parameters.params`（string），卡片侧 `params` **不逐键平铺**；解析须 `JSON.parse(want.parameters.params as string)` 后取 `mfa_action` / `mfa_item_id`（官方 `arkts-ui-widget-event-router.md` 示例原文）。
- **消费互斥**：`Index` 内用 `isConsuming` 互斥标志，避免 `@Monitor` 与 `onActive` 双路径并发；列表为空时先 `await refresh()`，且 `refresh()` 已有 `isFetching` 去重会在并发时直接返回（`Index.ets:498-500`）——因此消费前必须确认列表已就绪，否则只能等待重试。
- **失败不清空**：仅**复制成功**后清空 `CardAction`；失败保留待办（“无论成败都清空”会把一次瞬时失败变成永久失败）。
- **待办重试锚点**：在 `refresh()` 的 `finally`（`isFetching = false` 之后）重试消费待办 —— 关闭“热启动时页面未重新激活、且该次 refresh 被 `isFetching` 去重静默返回”导致待办永不消费的时序漏洞；`isConsuming` 使其无递归风险。
- **失败与永挂边界**：`refresh()` 失败会 reject（`Dialog.execute` → `Promise.reject`），故消费内部必须 try/catch 且三处调用点 `.catch()`；`refresh()` 成功但账号数仍为 0 → 清空待办（避免日后添加首个账号时意外自动复制）。
- **空列表点卡**：`ids` 为空时不做复制，只静默进入列表（首屏已可见添加入口），不弹「复制失败」。
- **监听必须用状态装饰器**：`@Monitor('cardAction.version')` 的目标变量须为 `@Local` 等状态装饰变量（官方 `arkts-new-monitor.md`：「未被状态变量装饰器装饰的变量无法被 @Monitor 监听到变化」），故 `cardAction` 定义为 `@Local`。

**边界（Must NOT）**：不做卡内按钮 message 事件、不做 FormExtensionAbility 算码、不放 secret、不做秒级刷新、不做 `dataProxy`、不做 `2*4`。

### 3.2 首屏信息密度改造（P0-2）

| 页面 | 改动 | 保持不变 |
|---|---|---|
| `pages/index/Index.ets:172 empty()` | 「图标 + 暂无数据」→ **首屏即功能**：标题块「开始保护你的账号」+ 3 条要点（离线计算 / 多设备同步 / 卡片桌面直达）+ 两个并列主按钮（扫码添加 / 手动输入，复用 `index_index_page_add_by_scan`、`add_by_input`）+ 次入口「查看使用帮助」 | `Refresh` / `Stack` / FAB / `bindMenu` 结构 |
| `components/IndexGuide.ets`（124 行） | 全屏 4 步 `Swiper` → 首页内**单屏紧凑说明块**（3 条要点行 + 「不再提示」），删除 `GUIDE_STEPS`/`swiper`/`guideIndex`；组件只保留 `onDismiss` 事件（原 `onScan`/`onInput` 由 `empty()` 的两个主按钮承担） | 引导文案键 `index_guide_page_step_*`、`IndexGuideState.isSkipped` 语义 |
| `components/TotpCard.ets` | 码右侧新增复制图标按钮（`action_icon_size`，非排序态渲染）→ 复制 + Toast | issuer/username 排版、`code_font_size` 大字、`Progress` 形态（**无徽标、无秒数**） |
| `pages/index/Detail.ets` | 大字码下方新增「复制验证码」按钮；新增「使用说明」卡片（离线计算 / 周期含义 / 左滑删除 / 卡片添加方式） | `Progress` 形态、现有 3 张信息卡（**无秒数环**） |
| `pages/user/Index.ets` | 新增统计行「已保护 N 个账号」（取自 `ItemsRuntime.ids.length`）+ 「使用帮助」入口（→ `user/help`）+ 「关于」入口（含 `App.version`） | 头像/昵称、现有「个人信息」入口 |
| `pages/user/Help.ets` | 静态使用帮助页（添加方式 / 卡片添加 / 离线与同步说明 / 删除与安全提示） | — |

**资源规范**（已验证）：新字符串加在 `entry/src/main/resources/base/element/string.json`，前缀沿用 `index_index_page_*` / `index_guide_page_*` / `index_detail_page_*` / `user_*` / `card_*`；尺寸加在 `AppScope/resources/base/element/integer.json`。跨模块通用文案才放 `AppScope/resources/base/element/string.json`。**本次新增文案的完整键名清单以可执行 plan 的 Task 1 为凭**（单一来源，避免两文档重复维护产生漂移）。

### 3.3 契约核对（标注来源）

| 契约 | 结论 | 状态 |
|---|---|---|
| 卡片配置文件字段、`supportDimensions` 取值、`updateDuration` 单位为 30 分钟 | OpenHarmony docs `arkts-ui-widget-configuration.md` | 已验证（外部官方源码） |
| 卡片渲染在系统统一进程，与提供方内存隔离；数据经 `LocalStorageProp`/`formBindingData` 注入 | `arkts-ui-widget-process.md`、`arkts-ui-widget-interaction-overview.md` | 已验证（外部官方源码）；**V2 接收机制见 §8** |
| `postCardAction` 支持 router/call/message；`call` 元服务暂不支持 | 官方文档 + 社区转述 | router 高 / call 限制 中 |
| 卡片刷新机制清单（定时 30min、`setFormNextRefreshTime` 最短 5min、`updateForm` 主动、`dataProxy` 仅系统应用） | 官方文档（被动刷新/页面刷新概述） | 已验证（外部官方源码） |
| `FormExtensionAbility` 独立进程、与主应用共享文件沙箱、创建后 10 秒无操作被清理 | `arkts-ui-widget-process.md`、`js-apis-app-form-formExtensionAbility.md` | 已验证（外部官方源码） |
| `postCardAction` 的 `params` 经 `want.parameters.params`（JSON **字符串**）传递，需 `JSON.parse` 后取值 | `arkts-ui-widget-event-router.md:110-123`（官方示例原文） | 已验证（外部官方源码） |
| `@Monitor` 目标变量必须被 `@Local`/`@Param`/`@Provider`/`@Consumer`/`@Computed` 装饰 | `arkts-new-monitor.md:28,156`（官方原文） | 已验证（外部官方源码） |
| `FormExtensionAbility.onAddForm(want): formBindingData.FormBindingData` 为**同步**签名，`onUpdateForm`/`onRemoveForm` 返回 void | SDK `@ohos.app.form.FormExtensionAbility.d.ts:83/129/207` | 已验证（本机 SDK 源码） |
| `preferences` 同步 API（`getPreferencesSync`/`getSync`/`putSync`/`flushSync`）存在且带 `@atomicservice` | SDK `@ohos.data.preferences.d.ts:452/1114/1480/1743` | 已验证（本机 SDK 源码） |
| `formInfo.FormParam.IDENTITY_KEY = "ohos.extra.param.key.form_identity"`（卡片 formId 取值） | SDK `@ohos.app.form.formInfo.d.ts:679` | 已验证（本机 SDK 源码） |
| `$r('sys.symbol.X')` 名称必须在编译期符号表 `sysResource.js` 中存在（如 `general_copy`/`arrow_2_circlepath`/`lock_shield`/`rectangle_on_rectangle` 均在；`doc_on_doc`/`arrow_triangle_2_circlepath` **不存在**） | SDK `ets/build-tools/ets-loader/sysResource.js` | 已验证（本机实测） |
| 卡片侧 `$r` 的**带参格式化**（`$r('app.string.x', arg)` / `%d`）支持 | 官方仅描述「卡片支持部分能力、接口带卡片能力标记」 | **未找到明确规定 → 设计规避（卡片只用无参 `$r` + 拼接）** |
| preferences / pasteboard 的接口带 `@atomicservice` 标注（在元服务 API 集内） | SDK d.ts 标注（`preferences`/`pasteboard`/`formProvider`） | 接口归属已验证；**运行时行为待真机 PoC（假设 A/B）** |
| 主应用 `Totp.all()` 依赖登录态（`PersistenceV2` Authorization + Http 拦截器） | `utils/Http.ets:10`、`api/Totp.ets` | 已验证（读过源码） |
| `EntryAbility` 当前不处理 want（无 `onCreate`/`onNewWant`，全文件 47 行） | `ability/EntryAbility.ets` | 已验证（读过源码） |
| 卡片数据必须经 `LocalStorageProp` 注入，卡片侧不能读 preferences | 同上进程模型文档 | 已验证（外部官方源码）；**2026-10-04 起卡片改用 V2 按变量名接收，见 §8** |
| 构建命令可用性 | 2026-10-02 实测：`hvigorw.js assembleHap --mode module -p product=default --no-daemon` → `BUILD SUCCESSFUL`，`git status` 无脏文件 | 已验证（本机实测） |

## 4. 推进策略

```
Task 0（可与 Wave 1 并行）环境与命令快照：真机型号/系统版本、hdc、构建命令、元服务调试签名
Wave 1（串行脚手架）Task 1：module.json5 卡片段 + form_config.json + EntryFormAbility 最小实现
                        + Card.ets 最小实现 + utils/Clipboard + utils/CardSnapshot
                        + App.ets(LogDomain.FORM) + routes.json(user/help) + Help.ets 占位
                        + string.json 全量新键 + AppScope/integer.json 新键
                        + 真机 PoC（preferences 跨进程 / pasteboard / router want / 卡片渲染）
Wave 2（串行）Task 2 卡片数据链路（EntryFormAbility 完整 + Card.ets 完整 + formId）
Wave 3（并行）Task 3 主应用接入 + 动作消费 ｜ Task 5 列表项复制按钮 ｜ Task 6 详情页 ｜ Task 7 我的页 + 帮助页
Wave 4（串行，独占 Index.ets）Task 4 空态重构 + 引导内嵌
Wave 5 Task 8 AGC 材料与审核回复文档
```

**回滚**：
- 卡片链路：**以 `git revert` 对应提交为准**（Task 1/2/3/8 各自独立提交）——因为 Task 3 已把 `CardSnapshot`/`CardAction`/`formProvider` 与消费逻辑写入 `pages/index/Index.ets`、`ability/EntryAbility.ets`、`App.ets`、`string.json`，仅删新增文件会编译失败；若只需临时停用，可先删 `module.json5` 的 `extensionAbilities` 段（卡片入口消失，但页面侧快照写入为无害旁路）
- 首屏链路：`git revert` 对应提交（Task 4/5/6/7）；无数据迁移，`IndexGuideState` 字段语义不变
- 若 Task 2 PoC 失败：卡片降级为“静态引导卡”（R1）；若 Task 3 假设 B/C 失败：降级为“直达详情页”（R2），首屏改造不受影响

## 5. 风险与对策

| # | 风险 | 严重度 | 对策 |
|---|---|---|---|
| R1 | preferences 在元服务 `FormExtensionAbility` 不可用 → 卡片拿不到账号数据 | 高 | Task 1 真机 PoC 先验；降级为静态引导卡（品牌 + 「点击查看验证码」），场景仍成立 |
| R2 | `pasteboard` 在元服务页面不可用 → "点卡片即复制"不成立 | 高 | Task 1 真机 PoC 先验；降级为"点卡片直达详情页"，复制由页内按钮完成 |
| R3 | router 事件拉起后 want 参数缺失/格式不符 | 中 | `onCreate`（冷启动）与 `onNewWant`（热启动）两路都实现并各测一次；参数缺失时静默进列表 |
| R4 | 卡片定时刷新有配额（50 次/日/卡），主动刷新依赖 formId 持久化 | 中 | formId 在 `onAddForm` 落 preferences、`onRemoveForm` 清除；仅数据真变更时 `updateForm` |
| R5 | 每声明一个尺寸需同尺寸快照素材，缺失导致 AGC 上传报错 | 中 | 首版只声明 `2*2`；快照素材与 AGC 说明列入 Task 8（人工出图） |
| R6 | 快照把 issuer/username 明文写入 preferences，扩大暴露面 | 中 | 只存展示字段（无 secret、无验证码）；代码注释与本文档标注该取舍 |
| R7 | 首页 `Repeat + virtualScroll`、`swipeAction`、`onMove` 索引耦合，新增元素可能错位 | 中 | 新增元素一律放在 `List` **之外**（`header()` 之上的独立块），不动 `List` 内部结构 |
| R8 | 列表项复制按钮点击同时触发"进详情" | 低 | 子组件 `onClick` 优先消费；若真机出现冒泡则用 `.hitTestBehavior(HitTestMode.Block)`；排序态不渲染该按钮 |
| R9 | 审核仍认为场景不足 | 中 | 回复附卡片截图/动图 + 首屏改版对比 + 附录候选清单作为 1.6.0 规划 |
| R10 | 卡片动作被双路径并发消费 → 重复复制/Toast 叠显，或一次瞬时失败后待办被清空（`refresh()` 的 `isFetching` 去重会让并发消费拿到空列表） | 中 | `isConsuming` 互斥 + 列表未就绪时不消费 + **仅成功后清空**；空列表点卡静默引导 |
| R11 | want 参数格式理解错误（误按平铺取值）导致取不到参数，从而把「解析错误」误判为「假设 C 证伪」而错误降级 | 中 | 按官方契约 `JSON.parse(want.parameters.params)`；失败时必须区分「参数缺失」与「解析/键名错误」再决定是否降级 |
| R12 | 卡片侧 `$r` 带参格式化（`%d`）支持未证实 → 卡片文案渲染异常 | 低 | 卡片侧只用无参 `$r`，数量行用 `Text(count)` + 固定后缀拼接；已写入详细设计 |

## 6. 监控与可观测性

复用现有 `hilog`（`LogDomain` 新增 `FORM = 4`），不新增上报通道：

```json
{"domain":4,"tag":"entryformability","event":"onAddForm","formId":"…","count":3}
{"domain":4,"tag":"entryformability","event":"onRemoveForm","formId":"…"}
{"domain":3,"tag":"pages/index","event":"cardAction","action":"copy","itemId":"…","result":"success|fail"}
```

| 指标 | 计算方式 | 关注阈值 |
|---|---|---|
| 卡片动作消费成功率 | `result=success` / `action=copy` 总数 | 真机验收期要求 100% |
| 快照读写失败率 | `CardSnapshot` 异常日志次数 | > 0 即排查 |
| 卡片刷新失败率 | `updateForm` 失败日志次数 | > 0 即排查 |

## 7. 附录：本次不做、候选清单

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

## 8. 变更记录（2026-10-04）：卡片状态管理 V2 迁移 + 卡片展示重排

> **状态**：经用户确认后实施（决策：① min API 由 6.0.0(20) 抬到 6.1.0(23)；② 展示优化做「档位 A+B」；③ 去掉冗余注入字段 `hasItems`）。
> **性质**：本节取代 §3.1「卡片数据注入约定」中关于 `@LocalStorageProp` / `hasItems` 的描述；§3 其余内容（快照链路、主动刷新、拉起链路、消费互斥）不变。

### 8.1 为什么要抬 min API

- ArkTS 卡片**自 API 23 起才支持状态管理 V2**（官方《卡片状态变量迁移》：V2 卡片按**变量名**匹配注入数据，入口组件用裸 `@Entry`、不再传 LocalStorage 实例；`@Local` 的「卡片能力」标注同样自 API 23 起）。
- 卡片 UI 跑在**系统卡片渲染服务进程**（非应用进程），因此这条能力由**设备系统版本**决定，不由编译 SDK 决定：在 API < 23 的设备上，V2 卡片推断为「数据永不刷新、恒显示默认值 0」的**静默失效**。为避免这种失败形态，min API 随之抬到 23。
- 代价（官方设备占比，2026-06-19 数据）：6.1.0(23) 60.20% + 6.1.1(24) 34.40% ≈ **94.6%**；`compatibleSdkVersion` 抬到 23 后，6.0.2(22)/6.0.1(21)/6.0.0(20) 及 5.x 合计约 **5.2%** 设备不再可安装。

### 8.2 改动清单

| 文件 | 改动 |
|---|---|
| `entry/src/main/ets/pages/card/Card.ets` | `@Component` → `@ComponentV2`；3 个 `@LocalStorageProp` → 2 个 `@Local`（`count` / `first`）；`hasItems` 删除，空态由 `count == '0'` 推导；拆 `Title()` / `Filled()` / `Empty()` 三个 `@Builder`；标题加品牌角标与 `Divider`；全部文本补 `maxLines(1)` + `textOverflow`；数量行改品牌色 + 小号后缀分层；`Blank()` 撑底 |
| `entry/src/main/ets/models/card/CardBridge.ets` | 去掉 `hasItems` 注入；新增 `CARD_FIELD_COUNT` / `CARD_FIELD_FIRST` 常量并以 `Record<string, string>` 装配，把「注入 key = 卡片 `@Local` 变量名」的契约写成显式注释 |
| `entry/src/main/ets/utils/CardSnapshot.ets` | `SNAPSHOT_MAX_ITEMS` 2 → 1（卡片只消费 `items[0]`，多存即多暴露 issuer/username） |
| `entry/src/main/resources/base/element/string.json` | `card_hint`：`点击查看验证码` → `点击复制验证码`（与「点卡即复制」的真实行为对齐） |
| `build-profile.json5` | 两个 product 的 `targetSdkVersion` / `compatibleSdkVersion`：`6.0.0(20)` → `6.1.0(23)` |

### 8.3 卡片展示改动明细

- **缺陷修复 1**：`first`（发行方）与标题此前**无 `maxLines` / `textOverflow`**，长发行方（如 `GitHub Enterprise Cloud`）会换行挤压 2x2 布局 → 全部单行省略。
- **缺陷修复 2**：`card_hint` 此前**在空态也渲染**（空列表点卡不会复制，只静默进列表），语义不成立 → 空态不再渲染底部提示。
- 文案对齐：`card_hint` 由「查看」改为「复制」，与 `postCardAction({mfa_action:'copy'})` 的真实行为一致。
- 视觉：标题加 16vp `Image($r('app.media.icon'))` 品牌角标 + 1vp `Divider()` 分栏；数量数字用 `$r('app.color.brand')` 加粗放大、后缀「个账号」降为 12fp 次要色；`Blank()` 让提示语贴底。
- **保持不做**（本次仍未做，理由见 §7 与 §8.5）：卡内实时验证码、卡内按钮、`dataProxy`、`2*4` 规格。

### 8.4 实施期实测（本机，非推断）

| 验证项 | 结论 |
|---|---|
| V2 卡片能否编译（`compatibleSdkVersion=6.0.0(20)`） | ✅ BUILD SUCCESSFUL，产物为 `class Card extends ViewV2`；V1 时代的 `'@Entry' should have a parameter` 告警消失（V2 本就不传 storage） |
| 抬到 `6.1.0(23)` 能否编译 | ✅ BUILD SUCCESSFUL（本机仅装 6.1.1(24) SDK，跨版本可用） |
| `@Builder` / `Blank` / `Divider` / `Image` / `maxLines`+`textOverflow` 在卡片中 | ✅ 编译全部通过 |
| 卡片组件白名单是否在编译期强制 | ❌ **不强制**：`SymbolGlyph` 不在 `ets-loader/form_components/*.json` 白名单中却编译通过 → 卡内「能不能用某组件」**只能靠真机判定**，不能靠编译 |
| `SymbolGlyph` 用于卡内图标 | **不采用**（不在卡片白名单，且编译期不拦） |

### 8.5 新增风险与验收要求

| # | 风险 | 对策 |
|---|---|---|
| R13 | V2 卡片的数据接收（按变量名匹配）**缺乏真机证据**，失败形态是静默不刷新 | 验收前必须真机跑：加 2 个账号 → 桌面加卡 → 应显示「2 个账号 + 首个发行方」；删 1 个 → 「1 个」；清空 → 空态。若恒为 0 → 判定 V2 接收失败 |
| R14 | min API 抬到 23 后 6.0.x/5.x 设备不可安装 | AGC 上架信息与版本说明需同步；如需保留老设备，只能回退卡片到 V1（见回滚） |
| R15 | 「注入 key = 卡片 `@Local` 变量名」是**编译期不可校验**的隐性契约 | 两侧文件头均已写明；改任一侧必须同步另一侧 |
| R16 | 卡内新增的 `Image` / `Divider` 属白名单内但无真机证据 | 真机验收时一并确认渲染正常；异常则先撤 `Image`，再撤 `Divider`（两处独立，可分级回退） |

**回滚**：卡片链路本次改动集中在 4 个文件 + `build-profile.json5`（1 行 ×2 处），`git revert` 单次提交即可；若只需临时规避 V2 风险而不回退 min API，需同时把 `Card.ets` 回退为 V1 接收方式。

## 9. 复盘（2026-10-04 晚）：卡片不刷新的真实根因是 preferences 跨进程缓存

> 现象：v1.5.0 装到模拟器后，添加账号，卡片仍显示空态；「过一会儿重新进负一屏」又正常了。
> 结论：**不是 V1/V2 的问题，也不是「preferences 跨进程不可用」（R1）**，而是**主应用进程缓存了 preferences 实例，读不到卡片提供方进程写入的 formId**。

### 9.1 根因链

1. 卡片添加 → `EntryFormAbility.onAddForm`（**提供方进程**）把 formId 写入 preferences（`mfa_card` / `card_form_ids`）。
2. 主应用（**另一个进程**）在卡片添加之前就已打开过 `mfa_card`，`preferences` 实例按进程缓存在内存里，**之后 getPreferences 不会重新读持久化文件** → `CardSnapshot.listFormIds()` 读到的是「没有 formId」的旧值。
3. `CardBridge.push()` 因 `formTargets.length <= 0` 直接 return → **`updateForm` 一次都没发出** → 卡片停在「添加卡片那一刻」的数据（那次 `count=0`）。
4. 应用被系统回收后重新启动（元服务进程存活很短）→ 实例重新从文件加载 → 读到 formId → 推送成功 → 卡片显示正确数据。这就是「什么都没做、重新进负一屏就有了」的真相：中间发生过一次应用重启。

### 9.2 证据（模拟器 OpenHarmony 6.1.1 / API 24，hdc 实测）

| 证据 | 内容 |
|---|---|
| 一次冷启动后的完整成功链路 | `sync: items=1` → `snapshot write count=1` → `push: formIds=1 targets=["564639218"]` → `updateForm 成功`；系统侧 `form_mgr_adapter[UpdateForm]` → `RequestRefresh` → `UpdateByProviderData` → `UpdateRenderingForm` → `form_cache_mgr[AddData]` → `refresh_cache_mgr[AddRenderTask]` |
| 跨进程 preferences 文件本身是共享的 | 提供方进程与主应用进程打印的 `context.filesDir` 一致（`/data/storage/el2/base/haps/entry/files`），快照 `rawLen` 非 0 —— **R1 证伪** |
| 卡片会应用推送值 | 用假数据探针推送 `first="Example*"`，负一屏卡片实际渲染出 `Example*`（截图确认） |
| 卡片视图是「每次可见时新建」 | 每次负一屏可见都打 `AceForm: JSForm Create, info.id: 564639218` → V1/V2 都在**创建时**注入最新数据，因此 **V2 卡片不是问题**（当时基于错误假设改的 V1 版本已还原回 V2） |
| 官方同款案例 | 华为 FAQ（HarmonyOS SDK 闭源开放能力 — Form Kit）与开发者论坛均有「卡片进程写 formId、主应用读不到；杀掉应用重启就能读到」的案例，官方解法即 `preferences.removePreferencesFromCache` 后再 `getPreferences` |

### 9.3 修复

`utils/CardSnapshot.ets` 新增 `private static prefs(context)`：先 `preferences.removePreferencesFromCacheSync(context, { name })` 再 `getPreferencesSync`，**write / read / addFormId / removeFormId / listFormIds 全部改走它**；`addFormId` / `removeFormId` 调整为先 `listFormIds`（内部已清缓存）再取实例写入，避免使用被逐出缓存的旧实例。

> 备注：官方文档同时说明 preferences「不保证多进程并发安全（只保证单进程安全）」，因此该方案是**读侧补偿**；若要彻底规避，可把 formId 改存普通文件（`filesDir` 下自管 JSON）。当前数据量极小、写入频率极低，采用官方推荐的清缓存读法。

### 9.4 风险表更新

- **R1（preferences 在元服务 FormExtensionAbility 不可用）→ 关闭**：文件沙箱共享，读不到是**进程内缓存**导致。
- **R13（V2 卡片数据接收）→ 降级为「已实测可用」**：V2 的变量名注入在卡片视图创建时生效；负一屏每次可见都会重建卡片视图，实测能拿到最新推送值。
- 新增 **R17**：任何新增的跨进程 preferences 读写若忘记清缓存，会复现同类静默故障 → 已写入 `AGENTS.md` 约束。
