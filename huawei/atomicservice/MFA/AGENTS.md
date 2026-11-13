# AGENTS.md

## 项目概述

该目录是华为元服务前端工程，当前工程名为 `MFA`，主要使用 ArkTS/ETS。

## 目录结构

```
MFA/
  AppScope/
  EntryCard/           # 卡片快照（服务卡片上架必需，见「服务卡片」节）
  entry/
    src/main/ets/      # 主要业务代码
    src/test/          # 本地测试
    src/ohosTest/      # Ohos 测试
  oh-package.json5     # 依赖定义
  oh-package-lock.json5
  build-profile.json5
  hvigorfile.ts
  code-linter.json5    # lint 规则
```

`entry/src/main/ets/` 下常见结构：

- `ability/`：Ability 入口（`EntryAbility.ets` 为 UIAbility；`EntryFormAbility.ets` 为服务卡片 FormExtensionAbility，由 `module.json5` 的 `extensionAbilities.srcEntry` 声明）
- `pages/`：页面；`pages/form/` 为服务卡片页面（由 `resources/base/profile/form_config.json` 的 `src` 声明，**不注册**到 `routes.json`）
- `components/`：公共组件；页面级组件按 feature 分子目录（如 `components/index/`）
- `api/`：接口调用
- `models/`：模型；按 feature 分子目录（`models/form/` 服务卡片相关、`models/totp/` TOTP 运行时、`models/security/` 安全设置与应用锁）
- `utils/`：工具函数（`utils/Prefs.ets` 为 **preferences 唯一入口**，见「本地存储」节；`utils/dialog/` 为弹窗窗口协调器，纯逻辑 + 单测，见「弹窗与认证跳转」节；纯策略类工具 `AppLockPolicy` / `AuthStatePolicy` / `SessionThrottle` / `SingleFlight` / `ItemFilter` / `ListViewState` 一律无 ArkUI 依赖，可单测）
- `themes/`：主题定义
- `types/`：类型定义

## 依赖与配置

- 依赖文件：`oh-package.json5`
- 锁文件：`oh-package-lock.json5`
- 工程配置：`build-profile.json5`、`hvigorfile.ts`
- lint 配置：`code-linter.json5`

已确认的依赖包括：

- `@ohos/axios`
- `@yansongda/otp`（ArkTS 端内 TOTP/HOTP 算码库，字节码 HAR）

依赖声明层级约定：**新增依赖声明在「使用它的模块」的 `oh-package.json5`**（`@yansongda/otp` 声明在 `entry/oh-package.json5`，ohpm 会生成模块级 `entry/oh-package-lock.json5`）。工程级 `oh-package.json5` 的既有依赖（`@ohos/axios`）保持不变，不迁移。官方依据见「字节码 HAR」节。新增/删除依赖后必须跑一次 `ohpm install --all` 让 `oh-package-lock.json5` 同步（锁文件要一起提交）。

## 环境与构建模式（ENV / BuildProfile）

- **环境地址不再由 `module.json5` 的 metadata 控制**：`entry/src/main/module.json5` 中的 `env` metadata 已移除，禁止再加回运行时手工切换的开关。
- 环境由**构建模式**在编译期注入，配置位置为工程级 `build-profile.json5` 的 `buildModeSet[].buildOption.arkOptions.buildProfileFields.ENV`：

  | 构建模式 | ENV | 说明 |
  |---|---|---|
  | `debug` | `test` | 本地 Run/调试；`<Default>` 下构建 HAP 也走这条 |
  | `release` | `prod` | 上架包；`<Default>` 下构建 APP 走这条 |
  | `test` | `test` | `ohosTest` 测试套自动使用该模式，缺条目会导致 ENV 未定义、编译失败 |

- 代码读取方式：`import BuildProfile from 'entry/BuildProfile'`（生成物位于 `entry/build/<product>/generated/profile/<target>/BuildProfile.ets`，**不入库**，由 `.gitignore` 的 `**/build` 覆盖）。
- **比较前必须转宽**：`BuildProfile.ENV` 是编译期字面量类型，先 `const env: string = BuildProfile.ENV;` 再比较；直接写 `BuildProfile.ENV === AppEnv.TEST` 在 release 构建会报 `This comparison appears to be unintentional because the types '"prod"' and 'AppEnv.TEST' have no overlap`。
- **新增自定义 buildMode 必须同时配置 `ENV`**，否则生成的 BuildProfile 里没有 ENV，引用处编译失败（fail-fast，优于静默连错环境）。
- 归属优先级：模块 target > 模块 buildOptionSet > 模块 buildOption > product > buildModeSet。**不要在 `products` 里写 `ENV`**，否则会压死构建模式差异。
- `products` 约定：`default`（release 证书）与 `debug`（debug 证书）**只允许 `signingConfig` 不同**。`signingConfig` 只能挂在 product 上，官方无「按构建模式自动切签名」能力，故两套 product 是必要的；debug 证书 Profile 的 `bundle-name` 与正式相同，因此两者 bundleName 必须一致，不能靠改 bundleName 做共存。
- 命令行构建/验证（`DEVECO` 按本机安装位置调整；与 DevEco Studio 界面构建等价）：

  ```bash
  export DEVECO=/Applications/DevEco-Studio.app
  export DEVECO_SDK_HOME="$DEVECO/Contents/sdk"

  # 本地调试包（debug 证书 + 测试环境）
  "$DEVECO/Contents/tools/hvigor/bin/hvigorw" \
    --mode module -p product=debug -p module=entry@default -p buildMode=debug assembleHap --no-daemon

  # 上架包（release 证书 + 正式环境）
  "$DEVECO/Contents/tools/hvigor/bin/hvigorw" \
    --mode module -p product=default -p module=entry@default -p buildMode=release assembleHap --no-daemon

  # 期望输出 0：包内不应再有 env metadata
  unzip -p entry/build/debug/outputs/default/entry-default-signed.hap module.json | grep -c '"env"'
  ```

- `entry/build-profile.json5` 当前不配置 `buildOptionSet`：原 `release` 条目仅重复默认值 `obfuscation.enable=false`，属空配置，已清理。若后续要启用 release 混淆，需重新加入 `buildOptionSet` 并做真机回归（工程大量使用 `PersistenceV2` 与 JSON 序列化，混淆需配套 keep 规则）。

## 字节码 HAR 与 useNormalizedOHMUrl（硬约束）

- 工程级 `build-profile.json5` 的 `strictMode.useNormalizedOHMUrl` **必须为 `true`**：一旦改回 `false`，依赖字节码 HAR（`@yansongda/otp`）会立刻构建失败，报 `00306046 Specification Limit Violation / Bytecode HAR [@yansongda/otp] not supported when useNormalizedOHMUrl is not true.`
- 官方依据：构建 HAR 文档「依赖字节码HAR包时，该工程的build-profile.json5中的 useNormalizedOHMUrl 必须设置为true」（[构建 HAR](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-build-har)）；工程级 build-profile.json5 文档「若工程引用了HAR/HSP，需确保工程的useNormalizedOHMUrl配置和HAR/HSP的useNormalizedOHMUrl配置保持一致，同时配置为true或false」（[工程级 build-profile.json5](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-build-profile-app)）
- 开启后须遵守：文件路径不含 `&`；不用相对路径跨模块或绝对路径导入；`oh-package.json5` 依赖别名须与依赖包 `name` 一致
- 该开关自 DevEco Studio 5.0.3.800 起为新工程默认值（本工程原先为 `false` 属遗留默认）

## lint 约束

- lint 主要覆盖 `**/*.ets`
- 忽略目录包括：`src/ohosTest/`、`src/test/`、`src/mock/`、`node_modules/`、`oh_modules/`、`build/`、`.preview/`
- 当前规则集包含性能与 TypeScript 相关推荐规则
- 安全相关规则对不安全加密算法有限制，修改安全或加密相关逻辑时要特别谨慎
- `@security/no-unsafe-mac`（warn）此前命中自研 `utils/Totp.ets` 的 HMAC-SHA1；改用 `@yansongda/otp` 后该告警不再出现在工程源码（`oh_modules/`、`src/test/**`、`src/ohosTest/**` 在 `code-linter.json5` 中被 ignore）。**规则与豁免策略不变**（不放宽规则、不加 disable 注释）

## 开发约束

- 新增或修改页面、组件、接口、模型时，优先沿用 `entry/src/main/ets/` 下现有目录组织
- 主题、公共组件、网络请求封装优先复用现有实现，避免重复创建近似能力
- 与后端 API 联动时，接口字段、鉴权语义、错误处理需与后端保持一致
- 弹窗/对话框统一用组件内的成员 `@Builder` 方法：**不要在 `Dialog.open/execute`、`Toast.execute` 等自定义函数的闭包里调用全局 `@Builder` 函数**（编译器不会给全局 builder 注入组件上下文，运行时报 `Cannot read property observeComponentCreation2 of undefined`）；因此加载/失败/重试弹窗各页保留自己的成员实现，不做跨页抽取
- 未确认工程已有命令前，不凭空引入新的构建或测试流程，优先遵循工程内现有配置文件
- ArkUI `ForEach` 的 keyGenerator **必须覆盖所有会影响该项渲染的数据**：key 不变时框架**不会**重新执行 itemGenerator，也不重建子项。分组/列表这类「同一 key 下成员会变」的场景必须把成员带进 key（如 `${kind}:${tag}:${ids.join(',')}`）；否则结构停留在旧值而内容已按 `@Trace` 刷新——典型表现：取消置顶后该项仍残留在「置顶」组、组头计数不更新。`components/SettingCard.ets` 的 `revision` 属于同类兜底手段。`Repeat` 不受此约束（按 key 精确 diff），新代码优先用 `Repeat`。
- 窗口隐私模式（防截屏）**只允许**经 `utils/PrivacyWindow.ets` 的 `apply(on, cause)` 修改；功能层统一走 `models/security/PrivacyWindow.ets`（`apply()` / `occlude()`），**禁止**在页面/组件里直接调用 `window.setWindowPrivacyMode`（同一主窗口实例上混用全局与页面级开关会互相破坏，官方 FAQ 有记载）。
- 安全设置（防截屏 / 应用锁）持久化：单库 `mfa` 下的**逐字段 key** `security.privacyWindow` / `security.appLock`（boolean），**每项设置只在自己的模型里读写**（`models/security/PrivacyWindow.ets` / `AppLock.ets` 的 `load` / `setEnabled`，均经 `utils/Prefs.ets`），不设中间 Store 层；写失败返回 `false` 且**不改内存**（先落盘、成功才改内存）；运行态（`AppLock.locked`、`PrivacyWindow` 的临时遮挡）**绝不落盘**。逐字段写入不需要 schema 版本号：缺省即默认值，**新增设置项 = 在 `utils/Prefs.ets` 登记一个 key + 在对应模型的 `load`/`setEnabled` 里各加一处读写 + 加一个默认值常量**。**一次只写一个 key**（逐 key 写无跨字段原子性）。
- 安全设置**端云同步**（`models/security/Sync.ets`，本地优先 + 脏标记）：`setEnabled` 落盘成功后只写 `security.dirty = true`（写失败只记日志，不改返回值），**模型不发网络请求**；`SecuritySync.flush(context)`（页面切换开关后 / `EntryAbility.onForeground`）在 dirty **且有 `accessToken`** 时把当前生效值整体上行到 `POST /api/v1/users/edit/config/mfa`（后端存 `config.mfa.security`，按叶子 merge），成功清 dirty；未登录不发请求（无意义且 401 会经 http 拦截器把用户踢回登录页）。**单飞期间的本地变更不能丢**：`_inFlight` 为 true 时 `flush` 直接返回，因此成功回调必须比对「已上行值 vs 当前生效值」，不一致就保留 dirty 并补发一次（否则那最后一次变更永不上行）。`SecuritySync.reconcile(context, server)` 只在登录成功后调一次（`pages/Login.ets` 的 `fetchUser`）：dirty → 先上行（本地为准）；否则服务端有值 → 经 `applyRemote` 恢复到本地；服务端无值 → 不动。`applyRemote` 只改 `enabled`，**绝不**碰 `AppLock.locked`，也不置 dirty。注销账号时调 `SecuritySync.clearDirty`（`pages/user/Delete.ets`）：服务端副本已随账号删除，残留 dirty 会让下一个登录的账号被本次的本地值覆盖。运行态永不参与同步。
- `models/security/` 下的模型统一契约：`instance()` 单例 + `load(context)` + `get enabled` + `setEnabled(context, on): boolean`；页面只读 `enabled` / `locked`，写入一律走 `setEnabled`（**先落盘、成功才改内存**）。
- **应用锁状态不变式**（`models/security/AppLock.ets`，安全关键）：`_verifying` 只在发起前置 `true`（**1 处**），复位必须恰为 **4 处**（`reset` / `onBackground` / 结果回调 / 同步异常兜底）；`_instance` 复位同为 4 处（结果回调内仅当 `=== instance`）；`_lastFinishedAt` 只在结果回调与同步异常里更新（**发起阶段不写**，否则失败分支会被自身 3 秒防抖挡住）；`_generation` 在发起时递增，另有三处作废点（`reset` / `onBackground` / 同步异常）。任一出口漏复位 `_verifying` = 「遮罩在、点解锁永远 `SKIPPED`」= 用户被锁死，属阻断级缺陷。改 `verify()` 后用下列数字复核（变了就要能解释原因）：

  ```bash
  F=entry/src/main/ets/models/security/AppLock.ets
  grep -c "this._verifying = true" $F   # 1
  grep -c "_verifying = false"     $F   # 4
  grep -c "_instance = undefined"  $F   # 4
  grep -c "_lastFinishedAt = "     $F   # 3
  ```

## 弹窗与认证跳转（防重叠）

- **三层职责**：`utils/dialog/WindowCoordinator.ets`（**纯逻辑**：单飞 / 租约 / 打开代号 / 等真实退场 / 打开超时 / 看门狗；ArkUI 调用与定时器全部注入，可在 `entry/src/test` 单测）→ `utils/PromptAction.ets`（唯一门面 `Dialog` / `Toast`，只负责把 ArkUI 的 `openCustomDialog` / `closeCustomDialog` 注入协调器）→ 页面 / `utils/SessionGuard.ets`（只决定「认证失效 → 是否跳登录页、跳几次、何时跳」）。**页面不要直接调 `promptAction`**，也不要绕过门面使用协调器。
- **loading 用租约**：`const lease = await Dialog.openLoading(builder)` → 必须 `await lease.release()`（`Dialog.execute` / `Toast.execute` 内部已配对）。同一时刻全局只有一个 loading 窗口，引用归零才真正关闭；租约带打开代号，`closeAllAsync()` 之后迟到的 release 是空操作，**不会误关下一轮窗口**。禁止再引入「页面自己开 / 自己关」的第二套计数。
- **重试 / 失败框走 `Dialog.openAlert`**（单槽位 + 并发串行化）。打开 loading 前协调器会先**主动关掉** alert 并等它真正退场，因此重试按钮的 action 里直接调用即可，**禁止再写 `setTimeout` 延迟**。
- **等待退场不要用固定时间片**：打开时注册 `onDidDisappear`（`promptAction.BaseDialogOptions`，**@since 12**；本项目 compatibleSdkVersion 23），按真实回调返回，仅在回调缺失时用 500ms 兜底。四个必须遵守的细节：
  - SDK 明确写了「消失动画被打断（例如同时触发弹窗关闭和页面切换）时 `onDidDisappear` 不回调」：`SessionGuard.redirectAsync` 正是「关框后立即 `pushPathByName`」，**真机上 500ms 兜底会比预期更常被走到**（不阻塞、不卡死，别当异常）。
  - 令牌在 `onDidDisappear` 里**只标记 `closed`、不删除**：`AlertDialogV2` / `LoadingDialogV2` 的按钮 action 执行完框架会自动关框，此时槽位仍指向该 id，删掉令牌会让下一次等待白等兜底超时、并对已不存在的 id 再关一次。
  - 打开窗口有 3s 超时：`openCustomDialog` 一旦不 settle，全局串行化锁会永久卡住，之后整个 App 开不出任何弹窗（兜底是「放弃本次窗口 + 记 error」）。
  - loading 有 45s 看门狗（必须大于最长请求超时），任何异常分支漏关时强关窗口，否则 `autoCancel: false` 的遮罩会永久挡住页面。
- **`AlertDialogV2` / `LoadingDialogV2` 的按钮 action 执行完毕就由框架自动关框**：不要在 action 里自己关闭窗口，也不要在 action 里同步开新窗口（用 `Dialog.openLoading` / `Dialog.execute` / `Dialog.openAlert`，它们会先等旧框真正退场）。这条前提若变化，需重新验证 `onDidDisappear` 仍会触发。
- **认证失效统一是 `AuthExpiredError`**（`utils/Errors.ets`）：Http 拦截器命中 `1000/1001/1002/1004/1005/1006` 时只调用 `configureHttp` 注入的 `authExpired` 回调并 reject；**Http 不得 import 模型 / 导航 / 提示等 UI 模块**。`Errors.ets` 只有 `HttpError`（可带后端业务码）与 `AuthExpiredError`，并用 `toError` / `errorMessage` 归一捕获值（catch 的运行时值可能不是 `Error`）。**不要再建错误分类枚举**——曾经有过 `ErrorKind`（network/timeout/server/auth/business），但没有一个读取方。
- **跳转登录页只走 `SessionGuard.redirect(state?, { throttle })`**：自动跳转走默认节流（1s 去抖 + 60s/3 次上限 + 先 `closeAllAsync()` 再入栈）；**显式跳转**（如注销账号后回登录页）传 `{ throttle: false }`——节流只该拦「同一个异常信号引起的重复跳转」。被忽略时日志带 `SessionThrottle.denyReason`（`in-flight` / `debounce` / `limit`），排查不必改代码加日志。页面**不得**自己 `pages.clear()` + `pushPathByName(LOGIN)`。`Dialog.execute` / `Toast.execute` 已统一跳过重试框与失败 toast，但**门面的跳过不覆盖页面级 catch**：自己 `try/catch` 后 `Dialog.openAlert(...)` 的页面（见 `pages/index/Index.ets` 的删除、扫码添加分支）必须自己判 `!(e instanceof AuthExpiredError)`。
- **接口统一走 `api/request.ets`** 的 `request` / `requestNoBody` / `requestVoid` / `requestVoidNoBody`：响应体形状校验（不是 `{ code, message, data? }` 形状按「服务器响应异常」处理，不留假业务码）、成功判定（`code === 0`）与 `HttpError` 构造只写一次。**无 body 的接口必须传 `undefined`**：`headers.post` 的 `Content-Type` 是 `application/json`，axios 会把 `null` 序列化成字面量 `"null"` 发出去。**`code === 0` 不等于 data 可用**：`access-token/login` 这类关键接口仍要在 api 层校验必填字段（`api/AccessToken.ets` 的 `assertUsable`），否则空 token 会写进 `Authorization` 让 `state()` 退化成 `EMPTY_AUTHORIZATION`，表现为「登录成功却反复回登录页」。
- **认证状态**：`State` 在 `types/Session.ets`（叶子），`LoginPageParams` 在 `types/Login.ets`；本地判定抽在 `utils/AuthStatePolicy.ets`（纯逻辑 + 单测）：只判「access_token 是否进入 5 分钟续期窗口」，**不再猜 refresh_token 的有效期**（曾经的「29 天」魔法常量是服务端契约的重复猜测）。`REFRESH_TOKEN_EXPIRED` **只可能来自拦截器**（1005/1006）。
  - `Authorization.refreshOnly()`：**非登录页只能用这个**（只续期，绝不拉起华为账号授权）。
  - `Authorization.ensure(state)`：**只允许登录页调用**——它在 `refresh_token` 失效时会降级 `login()`，也就是会拉起华为账号授权；从别的页面调用会与 `SessionGuard` 的跳转形成两条并发登录链路（两次 `loginWithHuaweiID` + 两次 `access-token/login`，服务端 upsert 互相覆盖）。
  - 登录页用 `SingleFlight` 做重入锁；成功路径 `await lease.release()` 之后再 `popIfSelf()`（只关栈顶登录页，避免返回手势后误关下层页）。
- **导航栈读取统一走 `utils/NavState.ets`**（`navPages` / `loginInStack` / `topPageName`），禁止自行 `AppStorageV2.connect(NavPathStack)` 后判断登录页。
- **首页 `pages/index/Index.ets` 的 `onActive` 刷新有门禁**：`SessionGuard.isLoginVisible()` 或 `Authorization.state() !== NORMAL` 直接返回；**例外**是 `NEED_REFRESH` 且本地还有 `refresh_token` → `renewThenRefresh()` 用 `refreshOnly()` 静默续期后再静默刷新（避免「回到首页既不刷新也不续期」，要等第一个请求拿到 1000 才闪一下登录页）。已有条目时 `refresh(true)` 静默刷新（不弹 loading），首屏与下拉刷新才用 loading；`refresh` 用 `SingleFlight`（`run` 共享在飞任务、`enqueue` 补一次带 loading 的刷新），下拉刷新会真正等待同一次请求。**`interactive` 与 `silent` 是两件事**：本地无条目时即使静默刷新也要弹 loading，失败也必须给提示（否则是「空列表 + 一次 loading + 什么都没有」）。
- **单飞统一用 `utils/SingleFlight.ets`**（`busy` / `run` / `enqueue`），不要再手写布尔位：布尔位靠 `finally` 或每个分支手动复位，漏一处就永久卡住。

## 服务卡片（`pages/form/`）

- 卡片使用**状态管理 V2**（`@Entry @ComponentV2`）：`updateForm` 注入的数据按**变量名**匹配卡片内的 `@Local` 变量，入口组件用裸 `@Entry`、**不传** LocalStorage 实例；`@LocalStorageProp` 等 V1 组件内装饰器在 `@ComponentV2` 中**编译报错**，两套不可混用。
- **注入契约**：卡片侧 `@Local` 变量名必须与 `models/form/FormBridge.ets` 的 `FORM_FIELD_*` 常量逐字一致。写错/改名**不会编译报错，只会静默不刷新**，改一侧必须同步改另一侧。
- 卡片状态管理 V2 自 **API 23（HarmonyOS 6.1.0）**起支持，因此 `build-profile.json5` 的 `compatibleSdkVersion` 不得低于 `6.1.0(23)`。
- 卡片内「能用哪些组件/属性」**编译期不校验**（SDK `ets-loader/form_components/*.json` 白名单不强制，如 `SymbolGlyph` 不在白名单也能编过），新增组件或属性一律以**真机验证**为准；优先复用已在卡片中跑通的能力（`Text` / `Row` / `Column` / `Blank` / `Divider` / `Image` / `Progress` / 通用属性）。
- **本地存储唯一入口是 `utils/Prefs.ets`（单库 + GSKV）**：全应用只有一个 preferences 库 `mfa`，`storageType` 首选 **GSKV**——主应用与卡片提供方（`FormExtensionAbility`）是两个进程，官方文档明确 XML 模式「不支持在多进程场景下使用」（文件损坏 + 数据丢失），GSKV「支持多进程并发读写」且逐 key 实时落盘。GSKV 不可用时（预览器 / 跨平台构建）`Prefs` 回落 XML（单进程），此时 `crossProcess: true` 会先 `removePreferencesFromCacheSync` 再读，保留旧的跨进程可见性语义。**任何新增 preferences 读写都必须经 `Prefs`**，禁止新增第二个库名，禁止在卡片内直接读 `preferences`。库名的存储类型创建后**不可切换**（XML 文件与 `.db` 互斥），故不要给已存在的库改名复用、也不要手工指定与既有文件不同的 `storageType`。
- **库 `mfa` 的 key 布局（唯一真相源 `utils/Prefs.ets`）**：`security.privacyWindow` / `security.appLock`（安全设置，主应用独写）、`security.dirty`（安全设置待上行标记）、`index.filter` / `index.grouped`（首页筛选与分组视图，`models/totp/ListViewStatePrefs.ets` 读写本地 KV（**不上云**），纯逻辑在 `ListViewState.ets`）、`form.snapshot`（卡片快照 object，主应用独写 / 卡片进程只读）、`form.id.<formId>`（**逐 formId 一个 key**，加卡删卡都是单 key 写删，避免两进程读改写同一数组丢更新）。新增数据一律先在此登记 key 常量，避免跨域撞名。
- 卡片渲染在系统进程、与提供方隔离，**不得**在卡内直接读 `preferences`、算码或放密钥；跨进程数据只能以字符串经 `formBindingData` 传递。
- 卡内交互**只用 `postCardAction` 的 `router` 事件**（不用 `message` / `call`）；入口用 `Text` + 通用属性（背景色 / 圆角 / `onClick`）充当按钮，组件与属性支持一律以真机为准。整卡 `onClick` 与子元素 `onClick` 并存时依赖「子组件优先消费」，真机需确认无冒泡重复触发。
- **卡片意图消费门禁**：卡片意图（`FormIntent`）统一由 `Index.consumeFormIntent()` 消费；未登录、应用锁锁定、页面未激活时必须保留 pending，不得执行扫码/跳转。`AppLock.unlockVersion` 仅用于解锁后重试（`locked` 是 getter，`@Monitor` 监听不到）；新增解锁入口必须让 `unlock()` 自增该版本。pending 意图超过 5 分钟 TTL 直接丢弃，避免取消解锁/登录后很久又突然触发。
- **卡片快照（上架必需，本地不报错）**：工程根必须有 `EntryCard/<模块名>/base/snapshot/<formName>-<尺寸>.png`，与卡片数量 **1:1** 对应（`<formName>` 取 `form_config.json` 的 `name`，尺寸取值 `1x2` / `1x1` / `2x2` / `2x4` / `4x4` / `6x4`，且**必须含 `2x2`**）。hvigor 的 `GeneratePackRes` 以 `existsSync(<工程根>/EntryCard)` 为开关，目录缺失时**静默跳过**：本地编译/签名/安装一切正常，但包内没有 `pack.res`，AGC 上传报**错误码 13「软件包中卡片与快照不符合要求」**。新增卡片或改尺寸时必须同步新增/替换快照。
- 快照是系统分发卡片时给用户的**预览图**（负一屏 / 应用市场 / 智慧搜索），必须是真实卡片截图：真机加卡（元服务运行中右上胶囊 `::` → Add widget）后截图裁剪，去掉桌面壁纸残色与边缘抗锯齿混色带，避免四角残留背景。
- 快照自检（不必完整构建即可验证结构；`DEVECO` 按安装位置调整）：
  ```bash
  # 1) 产出的包必须含 pack.res（体积约等于快照）
  unzip -l build/outputs/default/MFA-default-signed.app | grep pack.res

  # 2) 直接跑打包器 res 模式验证 EntryCard 树（依赖 build/outputs/default/pack.info）
  DEVECO=/Applications/DevEco-Studio.app
  "$DEVECO/Contents/jbr/Contents/Home/bin/java" \
    -jar "$DEVECO/Contents/sdk/default/openharmony/toolchains/lib/app_packing_tool.jar" \
    --mode res --entrycard-path "$PWD/EntryCard" \
    --pack-info-path "$PWD/build/outputs/default/pack.info" --out-path /tmp/pack.res --force true
  ```
  常见反例报错（便于搜索定位）：`The name is not same as formName`（文件名 ≠ form name）、`The level-4 directory of EntryCard must be named as snapshot`（四级目录名错）、`entry/<form>-2x2 has no related snapshot`（缺 2x2 快照）、`No image in PNG format is found`（非 PNG）。

## 加密备份（`pages/user/Backup.ets`，服务端加解密）

- 契约以 `application-rs/docs/backup-format.md` 为准（`POST /api/v1/backup/export|import`，`kind=totp`，信封 v1）；**加解密全部在服务端**，前端只做信封预检与口令策略，**禁止**引入端内 PBKDF2 / AES-GCM。
- 分层：`types/Backup.ets`（契约常量 / 信封类型 / `BackupPageParams`）→ `api/Backup.ets`（两个接口走 `api/request.ets` + 超时 15s + 后端业务码 → 文案）→ `models/Backup.ets`（`parseEnvelope` / 口令策略 / `buildExport`）→ `utils/BackupFile.ets`（文件通道）→ `pages/user/Backup.ets`（UI）。
- **备份接口超时固定 15s**（`BACKUP_TIMEOUT_MS`，服务端 PBKDF2 600k 迭代）；其余接口仍用默认 5s。
- **口令只存在于页面内存与请求体**：`onHidden` 调 `clearSecrets()`，不写 preferences、不进日志；导出文本与导入信封同样在 `onHidden` 清空。
- 通道：导出（复制到剪贴板 / `DocumentViewPicker.save` 存 `.mfa`）、导入（`PasteButton` 安全控件读剪贴板 / `DocumentViewPicker.select` 选文件 / 手动粘贴兜底，按内容识别不看后缀）。
- 读剪贴板**不要申请**受限权限 `ohos.permission.READ_PASTEBOARD`：只能用 `PasteButton` 授权成功后的临时权限（编译器会提示需要该权限，属预期告警）。
- 导入**不去重**；`9903` 表示部分写入，页面仍会刷新列表并提示核对。导入成功后用 `Totp.all()` 重载 `ItemsRuntime` 并 `FormBridge.sync` 同步卡片。
- 弹窗遵守租约约定（见上文「loading 用租约」）：`const lease = await Dialog.openLoading(...)` → `await lease.release()`；页面把「开窗 → 执行 → 关窗」收在 `withLoading()` 里，**先等 loading 真正退场再由调用方弹 toast**，避免提示叠在遮罩上。认证失效由 `SessionGuard` 接管，页面 `catch` 里只需跳过 `AuthExpiredError`，不要自己跳登录页。

## 测试

- 本地测试目录：`entry/src/test/`（`List.test.ets` 是唯一入口，新增文件必须注册进去）
- Ohos 测试目录：`entry/src/ohosTest/`
- 修改公共组件、页面跳转、接口调用或运行时模型时，应同步检查相关测试是否需要更新
- **纯逻辑必须可单测**：`AppLockPolicy` / `AuthStatePolicy` / `SessionThrottle` / `SingleFlight` / `ItemFilter` / `ListViewState` / `WindowCoordinator` 都不 import ArkUI，改动这些逻辑要补/改用例。窗口层与认证判定的历史 bug（孤儿弹窗、误关新窗口、登录态退化）都是靠「把决策抽成纯函数」才变得可验证的，不要再把并发/状态判定直接写进页面或 ArkUI 回调里。
- 命令行自检（无需 DevEco 界面，签名材料缺失也不影响编译）：
  ```bash
  cd huawei/atomicservice/MFA
  export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk   # 按本机 DevEco 安装路径调整
  HVIGORW=/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw

  # ArkTS 编译 + 打包（debug / release 都跑）
  "$HVIGORW" --mode module -p product=default -p buildMode=debug  -p module=entry@default  assembleHap --no-daemon
  "$HVIGORW" --mode module -p product=default -p buildMode=release -p module=entry@default assembleHap --no-daemon

  # 测试代码编译校验：Local Test 只能在 DevEco 里跑，但可以临时把用例复制到
  # entry/src/ohosTest/ets/test/ 并在那边的 List.test.ets 里 import（复制时把 import 路径
  # 的 `../main/ets/` 改成 `../../../main/ets/`），跑完即删
  "$HVIGORW" --mode module -p product=default -p buildMode=debug -p module=entry@ohosTest assembleHap --no-daemon
  ```
- 端内算码的真 crypto 路径**只在设备侧可验证**：官方「本地测试（Local Test）」明载不支持测试系统 API；库 barrel 顶层值导入 `internal/CryptoSource`（库内唯一 import kit 的文件）→ 真 crypto 用例放 `entry/src/ohosTest/ets/test/`（如 `TotpDevice.test.ets`，运行需真机/模拟器）

## 提交约束

- 禁止提交：`build/`、`oh_modules/`、`.hvigor/`、`.idea/`、`.preview/`
- 必须提交：`oh-package-lock.json5`、`entry/oh-package-lock.json5`、`EntryCard/` 下的卡片快照（上架必需，见「服务卡片」节）

## 联动开发说明

- 涉及后端接口联动时，同时参考根目录 `AGENTS.md` 与 `application-rs/AGENTS.md`
- 仅修改华为前端时，不需要遵循 Rust 或微信小程序目录下的专属规范

## NOTES

- `entry/src/main/ets/ability/` 目录包含 `EntryAbility.ets`（UIAbility 入口），上表已补充。
- `code-linter.json5` 包含 `@security/no-unsafe-*` 系列规则，修改加密/安全相关逻辑前请先确认不会触发 lint 错误。
- `build-profile.json5` 中的签名配置使用本机绝对路径引用证书/Profile/密钥库，签名口令为 DevEco 加密后的**密文**（非明文，换机通常不可直接复用）；证书与密钥库本体不入库，仅用于本地开发，禁止用于生产。
- 仓库 CI 目前**没有**华为前端的必跑门禁：`.github/workflows/huawei-atomicservice.yml` 是手动触发的脚手架（需要一台自带 DevEco 的 self-hosted runner，标签 `harmonyos`），接入常规 PR 门禁前请先按上面的「命令行自检」在本机跑一遍。
