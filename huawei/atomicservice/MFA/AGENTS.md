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
- `models/`：模型；按 feature 分子目录（`models/form/` 服务卡片相关、`models/totp/` TOTP 运行时）
- `utils/`：工具函数
- `themes/`：主题定义
- `types/`：类型定义

## 依赖与配置

- 依赖文件：`oh-package.json5`
- 锁文件：`oh-package-lock.json5`
- 工程配置：`build-profile.json5`、`hvigorfile.ts`
- lint 配置：`code-linter.json5`

已确认的依赖包括：

- `@ohos/axios`
- `@developers/dateformat`
- `@yansongda/otp`（ArkTS 端内 TOTP/HOTP 算码库，字节码 HAR）

依赖声明层级约定：**新增依赖声明在「使用它的模块」的 `oh-package.json5`**（`@yansongda/otp` 声明在 `entry/oh-package.json5`，ohpm 会生成模块级 `entry/oh-package-lock.json5`）。工程级 `oh-package.json5` 的既有依赖（`@ohos/axios`、`@developers/dateformat`）保持不变，不迁移。官方依据见「字节码 HAR」节。

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

## 服务卡片（`pages/form/`）

- 卡片使用**状态管理 V2**（`@Entry @ComponentV2`）：`updateForm` 注入的数据按**变量名**匹配卡片内的 `@Local` 变量，入口组件用裸 `@Entry`、**不传** LocalStorage 实例；`@LocalStorageProp` 等 V1 组件内装饰器在 `@ComponentV2` 中**编译报错**，两套不可混用。
- **注入契约**：卡片侧 `@Local` 变量名必须与 `models/form/FormBridge.ets` 的 `FORM_FIELD_*` 常量逐字一致。写错/改名**不会编译报错，只会静默不刷新**，改一侧必须同步改另一侧。
- 卡片状态管理 V2 自 **API 23（HarmonyOS 6.1.0）**起支持，因此 `build-profile.json5` 的 `compatibleSdkVersion` 不得低于 `6.1.0(23)`。
- 卡片内「能用哪些组件/属性」**编译期不校验**（SDK `ets-loader/form_components/*.json` 白名单不强制，如 `SymbolGlyph` 不在白名单也能编过），新增组件或属性一律以**真机验证**为准；优先复用已在卡片中跑通的能力（`Text` / `Row` / `Column` / `Blank` / `Divider` / `Image` / `Progress` / 通用属性）。
- **跨进程 preferences 必须清缓存后再读**：主应用与卡片提供方（`FormExtensionAbility`）是两个进程，`preferences` 实例按进程缓存在内存，某进程首次 `getPreferences` 后不再读持久化文件 → 看不到另一个进程刚写入的值。`utils/Form.ets`（`Snapshot`）已统一走 `prefs()`（内部 `removePreferencesFromCacheSync` 后再 `getPreferencesSync`）；**任何新增的跨进程 preferences 读写都必须复用该路径**，否则会出现「卡片添加后主应用读不到 formId → 不推送 → 卡片数据永远停在添加卡片那一刻」这类静默故障。
- 卡片渲染在系统进程、与提供方隔离，**不得**在卡内直接读 `preferences`、算码或放密钥；跨进程数据只能以字符串经 `formBindingData` 传递。
- 卡内交互**只用 `postCardAction` 的 `router` 事件**（不用 `message` / `call`）；入口用 `Text` + 通用属性（背景色 / 圆角 / `onClick`）充当按钮，组件与属性支持一律以真机为准。整卡 `onClick` 与子元素 `onClick` 并存时依赖「子组件优先消费」，真机需确认无冒泡重复触发。
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

## 测试

- 本地测试目录：`entry/src/test/`
- Ohos 测试目录：`entry/src/ohosTest/`
- 修改公共组件、页面跳转、接口调用或运行时模型时，应同步检查相关测试是否需要更新
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
- 当前仓库 CI 未包含华为前端的构建/lint 检查。
