# 华为 MFA 元服务：TOTP 计时改为单时钟派生（参数归一化 / 兜底 / 注销清理）

- 时间：2026-11-26
- 作者：pi agent
- 状态：已实施，PR #228 待人工合并 + 真机回归
- 范围：仅 `huawei/atomicservice/MFA/entry`。后端契约、preferences key 布局、服务卡片（`form.snapshot` / `form.id.*`）注入契约**均不变**
- 参照：`wechat/miniprogram/totp` v1.4~1.5（#225 全局整秒 ticker + `normalizePeriod`、#223 注销清空算码缓存）

## 1. 背景与问题

### 1.1 触发点：逐项盘点 totp 小程序 1.4~1.5 的可迁移项

| totp 变更 | 华为改造前现状 | 结论 |
|---|---|---|
| #225 全局整秒 ticker（N 卡片 2N 定时器 → 全局 1 个，对齐整秒，消除漂移） | `ItemRuntime.schedule()` 每条目 `setInterval` + `setTimeout`，倒计时靠本地递减 | **可迁移（本次做）** |
| #225 `normalizePeriod`（脏 period 回落 30s） | `schedule()` 只判 `> 0`；`ListItemCard` 用 `?? 30`、`Detail` 用 `?? 0`（`0` 不是 nullish，兜不住） | **可迁移（本次做）** |
| #223 注销清空算码实例缓存 | 无实例缓存，但 `ItemsRuntime` 持有全部条目明文 secret 且注销后不清 | **可迁移（本次做）** |
| #224 列表派生外提纯模块 | 已有 `utils/ItemFilter.ets` + `models/totp/ListViewState.ets` | 已等价，仅剩重复 `snapshot()`（见 §8） |
| #221 页面级应用锁守卫收敛 | 无逐页锁守卫：`LockScreen` 在 `Home` 统一套 | 已等价 |
| #222 `endpoint.ts` 统一错误包装 | `api/request.ets` 已收口（且更彻底） | 已等价 |
| #226 单字段编辑共用提交 | `EditText.ets` 已合并 issuer/username | 已等价（`Slogan.ets` 可并入，见 §8） |
| #220 底部 tabBar | 元服务是 Navigation 栈 + 「我的」页 | 不适用 |

### 1.2 自查发现的问题（改造前）

| # | 位置 | 问题 | 后果 |
|---|---|---|---|
| 1 | `ItemRuntime.schedule()` | 每条目 1×`setInterval` + 1×`setTimeout` = **2N 个定时器** | 定时器实际间隔 ≥1000ms 会累积漂移，各条目相位随运行时间发散 → 每秒 N 次**分散在不同帧**的重排 |
| 2 | `ItemRuntime.schedule()` | 倒计时靠 `progress--` 本地递减，与「验证码翻转」是两套时间算法 | 周期边界处进度条归零与翻码错开约 0.1~0.5s |
| 3 | `start/resume/stop` + `Index.onHidden` + `ListItem.onAttach/onDetach` + Ability 前后台 | 起停状态机共 **6 处**必须全部配对；`resume()` 靠 `_timeoutId !== undefined` 判断 | 漏一处即定时器泄漏或验证码冻结 |
| 4 | `ItemRuntime.set config` | 无条件 `this._progress = value.period` | `ItemsRuntime.reload()` 每次刷新都写 config → **每次返回首页进度条跳回满格** |
| 5 | `schedule()` / `ListItemCard` / `Detail` | `period` 未归一化；`?? 30`（列表）与 `?? 0`（详情）两处兜底不一致 | `period=0` 时 `schedule()` 直接 return（该条目**永不翻码**）、`Progress(total=0)`；小数 period 让进度值非整 |
| 6 | `ItemRuntime.freshCode()` | 每条目各自 `/totp/detail` 兜底 + 各自 `Toast` | N 条失败 = N 个请求 + N 条提示；断网时每 30s 刷一轮气泡 |
| 7 | `pages/user/Delete.ets` | 注销只清登录态/资料/筛选/脏标记 | `ItemsRuntime` 里**明文 base32 secret** 驻留到进程退出，换账号登录后旧条目仍被继续算码 |
| 8 | `Index.openDetail()` | 传 `new ItemRuntime(...)` 副本 | 详情页改标签/置顶要等一次网络刷新才同步；明文 secret 存两份 |
| 9 | `ItemRuntime` | `import Toast` + `import api/Totp` | 分层被打破，算码路径无法单测 |

## 2. 目标与非目标

**目标**

- 全应用**只有一个**秒级定时器，且与「验证码翻转」共用同一套时间算法；
- 倒计时与算码的**正确性不依赖页面/组件生命周期回调**（漏接线最多多算几次，不能冻结）；
- `period/digits/algorithm` 的兜底与校验**只做一次**，脏数据不再有第二种表现；
- 兜底请求与失败提示从「每条目一份」收敛为「每批一次」；
- 注销账号后明文 secret 立即释放；
- `models/totp/` 不依赖 UI 与网络，算码路径可单测。

**非目标**

- 不改后端接口、`preferences` key 布局、服务卡片注入契约；
- 不改 `@yansongda/otp` 依赖版本；
- 不做列表派生缓存（理由见 §8）；
- 不引入亚秒周期（统一 ticker 的粒度就是 1s）。

## 3. 整体方案

### 3.1 分层（改造后）

```
utils/Ticker.ets            对齐整秒的递归调度（定时器注入，可单测）→ 「最多 1 个定时器 / 停止不复活 / 退订即回收」
        │
models/totp/Clock.ets   @ObservedV2 单例 + @Trace nowMs；attach()/detach() 只由 EntryAbility 前后台驱动
        │                                    └─ 算码订阅（EntryAbility.wireClock 接线，进程内一次）
utils/Totp.ets              TOTP 参数与时间窗的唯一真相源：normalizePeriod/Digits/Algorithm/Config + stepOf/remainingOf
        │
models/totp/ItemRuntime.ets 只持有数据与算码结果：NormConfig、@Trace code、refreshIfNeeded(nowMs)、
                            remaining = 派生(nowMs, period)；不持定时器、不弹提示、不发请求
        │
models/totp/ItemsRuntime.ets 唯一算码驱动 onTick(nowMs)：窗口变了的条目才重算；算不了的条目同 tick 汇总成
                            一次 Totp.all()（SingleFlight）；失败经 onError 上报（60s 节流）；clearAll()
        │
UI（ListView / ListItemCard / Detail / Index / Delete）
                            Progress 直读 runtime.remaining / runtime.config.period；错误提示由页面决定
```

改造前：时间源与算码散在 `ItemRuntime` + 页面生命周期 + Ability 前后台，共 6 处起停点；
改造后：**时间只有 `nowMs` 一个来源、起停只有 Ability 一处入口**。

### 3.2 不变量（已写入 `huawei/atomicservice/MFA/AGENTS.md`）

1. 全应用只有一个秒级定时器；起停只由 EntryAbility 前后台驱动，页面切换不参与计时。
2. 倒计时是 `nowMs` 的**纯派生值**，禁止每秒本地递减，禁止为进度条新增第二份每秒变动的 `@Trace` 状态。
3. 算码驱动只有 `ItemsRuntime#onTick` 一个入口，只有「时间窗变了」的条目才重算。
4. `period/digits/algorithm` 归一化只做一次（`utils/Totp.ets#normalizeConfig`），模型之外不得再写 `?? 30`。
5. `models/totp/ItemRuntime.ets` 不得 import `utils/PromptAction` 与 `api/*`。
6. 详情页与列表共用**同一个** `ItemRuntime` 实例（路由参数传 id）。
7. 注销账号必须 `ItemsRuntime.clearAll()`。

### 3.3 关键决策：为什么选「派生」而不是「单定时器 + 每条目写状态」

| 维度 | 方案 A：ticker + 每条目写 `_progress` | 方案 B：单 `nowMs` + 派生（**采用**） |
|---|---|---|
| 定时器 | 1 | 1 |
| 每秒状态写入 | N 次 | **1 次** |
| 每条目需维护的计时状态 | `_progress` + 订阅句柄 + start/stop 幂等 | **无** |
| 正确性依赖 | 6 处生命周期全部正确配对 | **1 处**（Ability 前后台）；行级 `onAttach/onDetach` 退化为纯优化开关 |
| 可测性 | 需 mock 定时器 + 断言写入序列 | `remainingOf(nowMs, period)` 纯函数，零 mock |
| 漂移 | 无 | 无 |

选 B 的核心理由不是"更优雅"，而是**把状态删掉比修对更容易**：改造前所有疑难 bug（§1.2 的 3/4/5）都是"多份可变状态互相追赶"的产物。

**技术前提**：`ItemRuntime.remaining` 是普通 getter，内部读另一个 `@ObservedV2` 实例的 `@Trace nowMs`。
该形态在本工程已有等价验证（`Home` 读 `appLock.locked`、`Index` 读 `itemsRuntime.ids`）。
若真机发现进度条不刷新，降级路径（架构不变，均为一处改动）：

1. 给 getter 加 `@Computed`（官方文档明确依赖源自 `@Trace`，API 12 起支持、API 23 起卡片可用）；
2. 仍不生效则由 `ItemsRuntime#onTick` 给每条目写 `playing` 值（回到方案 A，仍只有 1 个定时器、同帧批处理）。

## 4. 详细设计

### 4.1 `utils/Ticker.ets`（纯调度，可单测）

- `TimerSource` 注入 `schedule/cancel/now`；`SystemTimerSource` 用 `setTimeout` 实现。
- `AlignedTicker`：`delay = periodMs - now % periodMs` → **对齐整秒**；回调里先清句柄再 `publish()`、
  再 `schedule()`；`schedule()` 一律先 `cancel()`（任意时刻最多 1 个定时器），且检查 `_running`
  （防止 tick 回调里调用 `stop()` 后被重新登记）。
- `publish()` 遍历订阅者副本并逐条 `try/catch`：一个条目算码失败不影响其它条目。

### 4.2 `models/totp/Clock.ets`

- `@ObservedV2` 单例（`AppStorageV2.connect`，与 `AppLock.instance()` 同模式）+ `@Trace nowMs`。
- `attach()` = `ticker.start()`（先立即推进一次，回前台不必等下一个整秒）；`detach()` = `ticker.stop()`。
- `subscribe(listener)` 给 `ItemsRuntime` 用；`publish()` 里**先写 `nowMs`、再通知订阅者**，
  保证订阅者算码用的时刻与 UI 派生的时刻一致。

### 4.3 `utils/Totp.ets`（参数与时间窗的唯一真相源）

由原 `utils/TotpParams.ets` + `utils/TotpProgress.ets` 合并而来（见 §8 决策记录）：

- `normalizePeriod`：正整数秒，否则 30；`normalizeDigits`：6~8，否则 6；`normalizeAlgorithm`：SHA1/256/512，否则 SHA1；
- `normalizeConfig` → `NormConfig`（`types/Item.ets`，全字段确定值，`secret?` 保留可选）；
- `stepOf(nowMs, period)` / `remainingOf(nowMs, period)`：与 `@yansongda/otp` 的 `TOTP#remaining()` 逐点对齐
  （用例锁定），`remaining ∈ [1, period]`，永不出现 0。

合并理由：这两个文件的**唯一**不变量是「period 必须是正整数秒」——`normalize*` 负责保证、`stepOf/remainingOf` 负责消费。
拆成两个文件时「保证」与「依赖保证」分居两地，正是脏 period 能一路漏到 UI 的成因。

### 4.4 `models/totp/ItemRuntime.ets`

删除：`_timeoutId`、`_intervalId`、`_progress`、`schedule()`、`rotate()`、`start()`、`resume()`、`stop()`、
本地递减、`Toast` / `api/Totp` 依赖（净减约 90 行）。

保留/新增的状态机（**仅两个**窗口序号，全部用于「不重复、不过期」）：

| 字段 | 含义 |
|---|---|
| `_attemptedStep` | 最近一次尝试端内算码的窗口（同窗口不重复尝试，避免每秒重复抛异常/打日志） |
| `_requestedStep` | 最近一次已发起服务端兜底的窗口（每窗口最多 1 次请求） |

「本窗口有没有可用验证码」**不另设字段**，由 `_code` 是否为 `undefined` 表达：换窗口时
`refreshIfNeeded` 先作废旧码（`setCode(undefined)`）再端内重算，因此
`_code === undefined` 严格等价于「本窗口没有可用码」。代价是**算码失败时不展示上一窗口的旧码**
（旧码必然被服务端拒绕），改为空白/未知。

`refreshIfNeeded(nowMs)` 返回 `RefreshOutcome`：

- `LOCAL`：窗口变了且端内算码成功；
- `NEED_SERVER`：本窗口仍无可用码且尚未发起过兜底（无 secret / 算码抛错 / 首次加载）；
- `UNCHANGED`：同窗口已处理过。

`applyServerCode(code, issuedAtMs)` 是服务端码的**唯一入口**（兜底请求返回 / 列表刷新带来的码共用）：
只在「本窗口还没有码」且「`issuedAtMs` 与当前时刻同一窗口」时落地，返回是否真正采用
（调用方据此决定要不要再发兜底请求）。`config` setter 只在 `period`/`secret` **真变了**时作废
上述两个序号与当前码（普通刷新不再打断倒计时，修 §1.2-4）。

### 4.5 `models/totp/ItemsRuntime.ets`

- `onTick(nowMs)`：`loginInStack()` 门禁 → 遍历 `_ids` → `refreshIfNeeded` → 汇总 `NEED_SERVER` →
  `fallbackFromServer(targets, issuedAtMs)`。
- `refresh(runtime, item, nowMs)`：`add` 与 `reload` 共用的「端内算码 + 服务端码补位」，
  返回是否还需要发兜底请求（响应里已带回本窗口的码时直接补位，不再多发一次请求）。
- `fallbackFromServer`：`SingleFlight<IItem[]>` + 一次 `Totp.all()`，把结果按 id 分发；
  `_fallbackIssuedAt` 记录真正发起请求的时刻（单飞期间的后来者不会改写它）。
- 失败：`AuthExpiredError` 直接返回（SessionGuard 已跳登录页），其余经 `onError` 上报，
  并做 **60s 节流**；端内算码恢复（`LOCAL`）时重置节流。
- `clearAll()`：清运行时映射 + id 顺序（注销链调用）。
- 删除 `start/stop/stopAll/resumeAll`（起停已归 `Clock`）。

### 4.6 UI 与生命周期

| 文件 | 改动 |
|---|---|
| `ability/EntryAbility.ets` | `resumeAll/stopAll` → `Clock.attach/detach`；新增 `wireClock()`（`_clockWired` 保证进程内只订阅一次），冷启动在 `loadContent` 回调里也 `attach()` 一次 |
| `components/index/ListView.ets` | 删 `.onAttach/.onDetach` 计时钩子；保留 `virtualScroll` 关闭的既有结论（幽灵行 / 滑出面板旧 id 问题与本次无关） |
| `components/index/ListItemCard.ets` | `Progress({ value: runtime.remaining, total: runtime.config.period })`，去掉 `DEFAULT_PERIOD` 兜底 |
| `pages/index/Index.ets` | `aboutToAppear` 接线 `itemsRuntime.onError → Toast`；`onHidden` 不再 `stopAll()`；`openDetail(id)` 传 id |
| `pages/index/Detail.ets` | `runtime` 由 `ItemsRuntime#get(id)` 取同一实例（默认 `ItemRuntime.empty()` 作首帧占位）；删 `onActive/onInactive` 计时；`@Local itemsRuntime` |
| `pages/user/Delete.ets` | 清理链加 `itemsRuntime.clearAll()` |

## 5. 行为变化（用户可见）

| 场景 | 改造前 | 改造后 |
|---|---|---|
| 进度条 | 每次下拉刷新 / 返回首页跳回满格 | 平滑，不再跳变 |
| 进度条与翻码 | 边界处错开 0.1~0.5s | 同帧翻转 |
| 兜底失败提示 | 每条目一条，断网时每 30s 一轮 | 每批一条，且 60s 内最多一条 |
| 详情页改标签/置顶 | 返回列表要等一次网络刷新才同步 | 立即同步（同一实例） |
| 注销账号 | 旧条目仍驻留内存并继续算码 | 立即清空 |
| 脏 `period`（0 / 小数） | 该条目永不翻码 / 进度条 0-0 | 按 30s 正常算码 |

## 6. 验证

### 6.1 编译（本机）

| 项 | 结果 |
|---|---|
| `assembleHap` `buildMode=debug` | `CompileArkTS` 通过 |
| `assembleHap` `buildMode=release` | `CompileArkTS` 通过 |
| 单测代码编译（临时复制到 `src/ohosTest`） | `OhosTestCompileArkTS` 通过，临时文件已删 |
| `SignHap` | 失败：`Signature material verification failed`（签名材料与本机绑定，`build-profile.json5` 未改，属既有环境问题） |

### 6.2 单测（`entry/src/test/TotpRuntime.test.ets`，20 例，已注册进 `List.test.ets`）

- `totp_params`：period 正整数保留 / 脏值（0、负数、小数、NaN、Infinity、缺失）回落 30；
  digits 6~8 / algorithm 大小写与未知值 / `normalizeConfig` 幂等与 secret 缺失语义。
- `totp_progress`：`remaining ∈ [1, period]`、与 `@yansongda/otp remaining()` 逐点一致（含 45s 周期）、
  边界处 `step +1` 且 `remaining = period`、时区偏移（+05:30）无关性。
- `aligned_ticker`：对齐整秒（距整秒 250ms → 750ms）、单定时器复用（重复 `start` / 运行期 `subscribe`）、
  每次 tick 后 1000ms 且不累积漂移、`stop` 取消、退订到 0 立即回收、tick 内 `stop()` 不复活、订阅者异常隔离。

### 6.3 真机回归清单（合并前人工执行）

- [ ] 3~5 个账号：进度条与验证码同帧翻转，无空档
- [ ] 反复进出详情页 ≥5 次：进度条不再跳回满格
- [ ] 退后台 2 分钟回前台：倒计时立即正确，无 0 / 负数 / 旧值
- [ ] 应用锁锁定、登录页在栈中：不刷新、不提示
- [ ] 注销账号：列表与「已保护 N 个账号」归零，旧条目不再算码
- [ ] 飞行模式 + 无 secret 条目：失败提示每 60s 最多一次
- [ ] 手工把某条 `period` 改成 0 / 2.5：不崩、按 30s 走

### 6.4 性能观测

DevEco Profiler：主线程 timer 回调由 `2N/秒` → `1/秒`；每秒 UI 刷新帧数由「最多 N 帧」→ 1 帧。

## 7. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 跨对象 `@Trace` 依赖未建立（progress 不刷新） | 仅进度条不动 | 三级降级（§3.3），架构不变；`@Computed` 为一行改动 |
| 删掉行级计时钩子后某路径「看着该停表」 | 多算几次 HMAC（非正确性问题） | 这是有意取舍：正确性不再依赖生命周期回调 |
| 详情页改传 id 后 `onReady` 晚于首帧 | 首帧显示占位空态 | 默认 `ItemRuntime.empty()` 占位；既有代码同样依赖 `onReady` 先于 build |
| 兜底批量失败时整体回退（原为逐条） | 单条失败不单独重试 | `_requestedStep` 保证每窗口 1 次，下一窗口自动重试 |
| 提示去重（60s 节流）改变提示频率 | 产品可见 | 断网场景噪声显著下降；恢复后立刻可再提示 |

回滚：整条分支共 6 个提交，按「纯新增纯逻辑 → 核心重构 → 安全修复 → 不变量文档 → 文件合并 → 设计文档」排列；
代码相关的 4 个提交任一 `git revert` 后都能独立编译（后两个为文档/纯改名，不参与运行路径）。

## 8. 决策记录与遗留

**已决：`utils/TotpParams.ets` + `utils/TotpProgress.ets` 合并为 `utils/Totp.ets`**
（同时删除未被生产代码使用的 `windowOf` / `TotpWindow` / `ratio`——进度条用 `value=remaining / total=period`，不需要 ratio）。
理由见 §4.3；当时也评估过「保留两个小文件」（与工程内 `AppLockPolicy`(19 行) / `Display`(9 行) 的单文件风格一致），
最终以「不变量同址 + 单一消费者」为准。

**有意不做（并说明理由，避免成为隐性债务）**

- 列表派生缓存：`ListView` 单次 build 会调 `snapshot()` 2~3 次，但 snapshot 只复制 5 个轻量字段、条目量级个位到几十，
  缓存反而引入失效风险；
- `ItemRuntime.empty()` 作为 `@Param` 默认占位：保留是为了让 UI 不必到处判空，已注明可用 `id.length === 0` 识别；
- `Slogan.ets` 并入 `EditText` 式共用提交流程：属另一处重构，与本次计时链路无关。

**后续可做**

- 若未来需要环形进度条，再按需求引入 `ratio`（不要提前建）；
- `Index.doRefresh` 的 `reload()` 与 `ItemsRuntime` 的兜底 `Totp.all()` 是两条独立取数路径，
  极端情况下同一秒可能各发一次；如需可合并为同一 `SingleFlight`。
