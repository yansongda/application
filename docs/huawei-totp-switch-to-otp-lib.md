# 华为元服务 MFA：端内算码改用三方库 `@yansongda/otp`（替换自研 utils/Totp.ets）

> **时间**：2026-10-05
> **作者**：DeepSeek V4.1 Flash + yansongda
> **状态**：经过人工审核确认

## 1. 背景与问题

**现状**（均已读源码验证）：

- 华为元服务端内算码由自研文件 `huawei/atomicservice/MFA/entry/src/main/ets/utils/Totp.ets`（157 行）承担：`base32Decode` / `counterToBytes` / `truncate` / `zeroPad6` + `TotpCode.compute(secret, period, ms)`（cryptoFramework HMAC-SHA1，异步）。
- 唯一生产调用点：`entry/src/main/ets/models/totp/ItemRuntime.ets:7`（import）与 `:195`（`await TotpCode.compute(...)`）；失败回落 `POST /totp/detail`（`:202-210`）。
- 唯一测试调用点：`entry/src/test/TotpCode.test.ets`（11 个白盒用例）+ `entry/src/test/List.test.ets:2` 注册。
- 同族能力已由作者本人的 ArkTS 库 `@yansongda/otp` 实现并在 ohpm 发布（源码仓库 `~/000-Coding/ohos-otp`）：RFC 4226/6238、默认 SHA1 + 6 位、`remaining()` / `progress()`、统一 `OtpError` 错误码、库内自带 RFC 4226 Appendix D（10 条）+ RFC 6238 Appendix B（18 条）全量向量测试与设备侧真 crypto 用例。

**困境**：

1. 自研密码学实现（base32 末组截断、64 位计数器高低位、动态截断）需自行维护与自证正确性，且无法在多个端间复用。
2. 该文件命中 `@security/no-unsafe-mac`（HMAC-SHA1）告警（本工程配置为 warn；条数无来源，且本机无 code-linter CLI 可复现，故不标注数量）——按既定决策「不放宽规则、不加豁免注释」，属不可消除的长期噪声。
3. 作者侧已有更完备的实现与测试矩阵，MFA 侧的同份逻辑属重复劳动。

**目标**（约束条件）：

- **删除自研 `utils/Totp.ets`**，端内算码改由 `@yansongda/otp` 承担
- **行为零变化**：同一时间窗内验证码与后端 `build_noncompliant`（SHA1 + 6 位 + `config.period`）逐位一致；倒计时区间仍为 `[1, period]`
- **降级路径不变**：secret 缺失/为空 → 直接回落；算码异常 → 回落 `POST /totp/detail`
- **零后端改动、零微信端改动、零服务卡片逻辑改动**
- **可一键回退**（构建配置 + 依赖 + 代码，均无数据/协议变更）
- **不新增任何自研密码学代码**

## 2. 整体方案

**核心思路**：**把端内算码实现从「自研 utils 文件」换成「ohpm 三方库 `@yansongda/otp` 的 `TOTP` 类」；因该库以字节码 HAR 形态发布，主工程必须把 `useNormalizedOHMUrl` 由 `false` 改为 `true`（官方硬约束，已实测）。**

```
【改造前】
ItemRuntime.freshCode()
  └─ secret 存在 ──▶ TotpCode.compute(secret, period, now)      ← 自研 utils/Totp.ets
  │                   └─✗ 抛错 ──┐
  └─ secret 缺失 ────────────────┴──▶ POST /totp/detail（兜底，网络）──▶ 展示 code

【改造后】
ItemRuntime.freshCode()
  └─ secret 存在 ──▶ new TOTP({secret, period}).generate()      ← @yansongda/otp（bytecode HAR）
  │                   └─✗ OtpError ─┐
  └─ secret 缺失 ───────────────────┴──▶ POST /totp/detail（兜底，网络）──▶ 展示 code

构建期：MFA build-profile.json5  useNormalizedOHMUrl: false → true
        （否则 hvigor 直接拒绝字节码 HAR：00306046 Specification Limit Violation）
倒计时：ItemRuntime.schedule() 的 progress 公式一行不动（与库 remaining() 语义同式）
```

**文件结构**（变更后）：

```
huawei/atomicservice/MFA/
├── build-profile.json5                     [改] 两个 product 的 strictMode.useNormalizedOHMUrl → true
├── oh-package.json5                        [不动]（依赖声明在 entry 模块级，不写工程级）
├── oh-package-lock.json5                   [不动]（工程级锁不记录模块依赖；enableUnifiedLockfile=false）
├── AGENTS.md                               [改] 依赖清单 + useNormalizedOHMUrl 硬约束 + 依赖声明层级 + 测试分层 + lint 说明 + 提交约束
├── entry/
│   ├── oh-package.json5                    [改] dependencies 新增 "@yansongda/otp": "^1.0.2"
│   ├── oh-package-lock.json5               [新] ohpm 自动生成（必须提交）
│   └── src/
│       ├── main/ets/utils/Totp.ets         [删] 157 行自研实现
│       ├── main/ets/models/totp/ItemRuntime.ets [改] import（:7）+ 调用点（:195）
│       ├── test/TotpCode.test.ets          [删] 被测对象消失（原语已由库内向量测试覆盖）
│       ├── test/List.test.ets              [改] 摘除 totpCodeTest 注册
│       ├── ohosTest/ets/test/TotpDevice.test.ets [新] 设备侧真 crypto 黄金向量用例
│       └── ohosTest/ets/test/List.test.ets [改] 注册新套件
└── （其它文件零改动：api/Totp.ets、types/Item.ets、pages/**、components/**、models/form/**、EntryCard/**）
```

> 仓库文档落位：技术设计 `docs/<name>.md` 入库；`docs/implementation|evidence|learning/` 按既有约定被 gitignore（工作文档不入库）。

## 3. 详细设计

### 3.1 工程配置与依赖（全部实测，非推断）

| 项 | 结论 | 状态 |
|----|------|------|
| 字节码 HAR 与 `useNormalizedOHMUrl:false` 不兼容 | hvigor 报 `00306046 Specification Limit Violation / Bytecode HAR [@yansongda/otp] not supported when useNormalizedOHMUrl is not true.` → **BUILD FAILED** | **已验证（本机实测复现）**；官方原文：「依赖字节码HAR包时，该工程的build-profile.json5中的 useNormalizedOHMUrl 必须设置为true。」 |
| 改为 `useNormalizedOHMUrl:true` 后可编译 | `assembleHap`（debug）→ `BUILD SUCCESSFUL`；`CompileArkTS` 正常消费库的 `.d.ets` 声明 | **已验证（实测）** |
| 应用级 release 打包 | `assembleApp --mode project -p product=default -p buildMode=release` → exit 0；`MFA-default-signed.app` 334 086 B、`pack.res` 105 415 B（卡片快照链路正常） | **已验证（实测）** |
| 依赖声明层级 | 声明在 **entry 模块级**：`ohpm install`（根目录执行）写入 `entry/oh-package.json5`，生成 `entry/oh-package-lock.json5`，依赖落地 `entry/oh_modules/@yansongda`（已被 `entry/.gitignore` 忽略）；工程级锁不变 | **已验证（实测）** |
| 官方对声明层级的建议 | 「当前模块使用到的依赖配置在本模块的oh-package.json5中」；表 1「编译行为差异说明」中，**消费方=编译 HAP** 时「字节码HAR 三方包依赖 × 工程级 dependencies」记为 `/`（编译和运行都正常），仅当消费方本身是**待集成的字节码 HAR** 时才记为 `3`（后续集成可能运行时异常） | 官方文档原文（见附录 B） |
| 版本选择 | ohpm registry `latest = 1.0.2`（2026-10-06T09:03Z 发布；spike 期尚为 1.0.1）→ 依赖约束 `^1.0.2`。`v1.0.1..v1.0.2` **无任何 `.ets` 变更**，`library/oh-package.json5` 仅 `version` + `homepage` 两行差异（功能等价、元数据同构：`byteCodeHar`/`compatibleSdkVersion 20`/`useNormalizedOHMUrl:true`/零依赖均不变） | **已验证（查 registry + 仓库 `git diff v1.0.1 v1.0.2`，2026-10-06）** |
| 库兼容性前提 | 字节码 HAR `compatibleSdkVersion = 20` ≤ 工程 `6.1.0(23)` ✅；`useNormalizedOHMUrl=true` 的附带约束（路径不含 `&`、不允许跨模块相对/绝对路径导入、依赖别名须与包 name 一致）MFA 均满足 | 官方文档原文 + MFA 源码核对 |
| 运行时真机行为 | 无设备连接（`hdc list targets` 为空），未验证 → 列为发布前强制人工门槛 | **推断（未实测）** |

**配置变更示例**（工程级 `build-profile.json5`，两处 product 相同）：

```json5
"buildProfile": {
  "strictMode": {
    "caseSensitiveCheck": true,
    "useNormalizedOHMUrl": true      // false → true（default / debug 两个 product 各一处）
  }
}
```

**模块级依赖声明**（`entry/oh-package.json5`）：

```json5
"dependencies": {
  "@yansongda/otp": "^1.0.2"
}
```

**生成的模块锁**（`entry/oh-package-lock.json5`，ohpm 自动生成，禁止手改；下为 1.0.2 解析结果**节选**——完整结构还含顶层 `meta`（`stableOrder`/`enableUnifiedLockfile`）与条目内 `name`/`version`，见契约快照 §6；spike 期实测为 1.0.1，锁结构一致）：

```json5
{
  "lockfileVersion": 3,
  "specifiers": { "@yansongda/otp@^1.0.2": "@yansongda/otp@1.0.2" },
  "packages": {
    "@yansongda/otp@1.0.2": {
      "resolved": "https://ohpm.openharmony.cn/ohpm/@yansongda/otp/-/otp-1.0.2.har",
      "integrity": "sha512-JqTuDEB4BKTUOCbdYJ9EQxqci1n5JwCPj2205WubGpj4EfPuv88nEqp0NS90dyvdVIM+GZ42chIPo8iT5jcLww==",
      "registryType": "ohpm"
    }
  }
}
```

### 3.2 契约对照（库 API vs 现有实现）

| 现有行为 | 库 API | 状态 |
|----------|--------|------|
| `TotpCode.compute(secret, period, ms)`（`async`） | `new TOTP({secret, period}).generate(ms?)`（**同步**；`ms` 缺省 `Date.now()`） | 已验证（读库源码 `TOTP.ets`） |
| 强制 SHA1 + 6 位（忽略 URI 中 algorithm/digits） | 默认 `OtpAlgorithm.SHA1` + `digits = 6`；库支持 SHA256/512 但我们不传 | 已验证 |
| secret 宽松解析（去空白、转大写、去尾部 `=`） | `Secret.fromBase32` 同规则 | 已验证（读 `internal/Base32.ets`） |
| 空 secret / 非法字符 / 0 字节 → 抛错触发回落 | `EMPTY_SECRET` / `INVALID_BASE32_CHAR` / `SECRET_TOO_SHORT`（`OtpError extends Error`） | 已验证 |
| `period` 必须正整数（非整数/0/负 → 抛错） | `INVALID_PERIOD`；`minSecretBits` 默认 `0`（不强制密钥强度，兼容 80 bit 存量密钥） | 已验证 |
| 倒计时 `period - (epoch秒 % period)` | `remaining()` = `period - (((s - t0) % period) + period) % period`，`t0=0` 时**同式等价** | 已验证（读 `internal/TimeStep.ets`） |
| 失败归一化抛错、不打印 secret | 错误消息固定文案，不含 secret/token；`Secret.toJSON()` 返回 `'[REDACTED]'` | 已验证（读库源码 + README） |

### 3.3 代码改动（伪代码）

`ItemRuntime.ets` 仅两处（其余方法与字段零改动）：

```
- import { TotpCode } from '../../utils/Totp';
+ import { TOTP } from '@yansongda/otp';

  async freshCode() {
    const seq = ++this._computeSeq;                       // 竞态序号：不变
    const secret = this._config.secret;
    if (secret 存在且非空) {                               // 判空：不变
      try {
-       const code = await TotpCode.compute(secret, this._config.period, Date.now());
+       const code: string = new TOTP({ secret: secret, period: this._config.period }).generate();
        if (seq === this._computeSeq) this._code = code;    // 不变
        return;
      } catch (e) {
        hilog.warn(..., '端内算码失败，回退服务端: id=%{public}s', this._id);   // 不变：只记 id，不含 secret
      }
    }
    const detail = await Toast.execute(() => Totp.detail(this._id), ...);       // 兜底：不变
    if (seq === this._computeSeq) this._code = detail.code;
  }
```

**边界与不变项**：

- `start()` / `resume()` / `stop()` / `schedule()` / `rotate()`、`progress` 递减循环、`period > 0` 守卫：**一行不动**。
- 倒计时**不**改用库的 `remaining()`：库实例构造依赖合法 secret/period，换成库会把「倒计时」与「算码可行性」耦合；现式与库语义同式等价，保留可把爆炸半径压到最小。
- **不缓存 TOTP 实例**：每次 `freshCode()` 现构造，与现状「无状态 compute」等价，避免 secret 变更后实例陈旧（base32 解码成本可忽略）。
- `catch (e)` 中不使用 `e`（与现状一致），不把错误细节引向日志或 UI。

### 3.4 测试与验证策略

| 层 | 动作 | 理由 |
|----|------|------|
| `entry/src/test/TotpCode.test.ets` | **删除** + `List.test.ets` 摘除注册 | 被测对象已删除；其覆盖的 base32/计数器/截断/补零原语由库内 RFC 4226 Appendix D（10 条）+ RFC 6238 Appendix B（18 条）向量测试覆盖 |
| 本地新增用例 | **不新增** | 官方「本地测试（Local Test）」明载「当前不支持测试 C/C++ 方法及系统 API」；库 barrel 顶层值导入 `internal/CryptoSource`（库内唯一 import kit 的文件，进而引入 `@kit.CryptoArchitectureKit`），本地加载结果不确定，不值得引入不确定性 |
| `entry/src/ohosTest/ets/test/TotpDevice.test.ets` | **新增** 4 条：`T=59 → 287082`、`T=1234567890 → 005924`、`remaining(59000) == 1`、`generate()` 返回 6 位数字 | 真 crypto 路径只能在设备/模拟器侧验证；这是「码是否与后端一致」的唯一自动化护栏 |
| 构建门禁 | `assembleHap`（debug / ohosTest target）、`assembleApp`（release） | 三条命令均已实测可用（见附录 A） |
| 真机冒烟 | 首页/详情页验证码与后端一致、周期翻转、飞行模式亮码、服务卡片渲染 | **用户执行**（本机无设备），发布前强制门槛 |

### 3.5 性能与影响

| 指标 | 改造前 | 改造后 |
|------|--------|--------|
| 调用形态 | `await` 异步（每周期 1 次） | **同步**（cryptoFramework `*Sync` 链路；HMAC-SHA1 微秒级，主线程阻塞可忽略） |
| MFA 侧代码量 | 157 行实现（`wc -l`）+ 121 行白盒测试（`wc -l`） | 0（1 行 import） |
| 包体 | — | +9.6 KB（324 497 B → 334 086 B，字节码合并进 `ets/modules.abc`） |
| 依赖数 | 2 runtime（axios、dateformat） | 3（`@yansongda/otp` 自身零依赖） |
| lint | 自研文件命中 `@security/no-unsafe-mac`（warn；条数本机不可复现） | MFA 源码**零 MAC API 引用**（等价验证：`grep -rn "cryptoFramework\|createMac\|createSymKeyGenerator" entry/src/main/ets` 无输出）；`oh_modules/`、`src/test/**`、`src/ohosTest/**` 在 `code-linter.json5` 中被 ignore；库内部同样不添加豁免注释。本机无 code-linter CLI，全量 lint 留 DevEco 人工执行 |
| 请求量 | 每周期 0 次端内 / 兜底 detail | 不变（端内算码为权威来源） |

### 3.6 兼容性与降级

| 场景 | 改造后行为 | 与改造前对比 |
|------|------------|--------------|
| `secret` 为 `undefined` / 空串 | 跳过端内，直接回落 `/totp/detail` | 相同 |
| secret 非法字符 / 解码 0 字节 | 库构造抛 `OtpError` → catch → 回落 `/totp/detail` + hilog（仅 id） | 相同（错误码更精确，但未写日志） |
| `period ≤ 0` | `schedule()` 守卫拦下（不建定时器）；`freshCode()` 内构造抛 `INVALID_PERIOD` → 回落 detail | 相同 |
| `period` 非整数 | 库抛 `INVALID_PERIOD` → 回落 detail | 相同（自研 `Totp.ets:129-131` 本就校验 `Number.isInteger` 并抛错，非「新收紧点」） |
| 端内与后端同时失败（离线） | 保留最后一次 `code`，无则空串 + Toast | 相同 |
| 服务卡片（`pages/form/`） | 不经过 `ItemRuntime`，零影响 | 相同 |
| 历史版本共存 | 纯前端构建配置 + 依赖变更，无后端/数据/协议变更 | — |

### 3.7 本次不做

- 不改后端（`application-rs/**`）、不改微信端（`wechat/**`）、不改卡片逻辑
- 不改 `api/Totp.ets` 兜底通路、不改 `types/Item.ets`、不改 `schedule()` 倒计时公式
- 不在 `docs/` 之外新增脚本或 CI job
- 不改 `AppScope/app.json5` 版本号、不改 `CHANGELOG.md`（发布时按 release skill 统一记）
- 不在 otp 仓库做任何改动（`sourceMapsPath` 元数据另议）
- 不迁移既有 `@ohos/axios` / `@developers/dateformat` 的声明层级（避免无关变更）

## 4. 推进策略

```
Phase 0 契约 spike —— 本轮调研期已完成（在 /tmp 复刻工程实测，未触碰仓库）
├─ 逐项实测：HAR×false 必失败 / true 可编译 / 应用级 release 打包 / 模块级依赖声明 / ohosTest target 可编译
└─ 证据落盘：docs/evidence/huawei-totp-switch-to-otp-lib/task-0-spike.md
Phase 1 工程配置（entry/oh-package.json5 + entry 锁 + build-profile）
└─ 验证点：ohpm install 成功、entry 锁生成、assembleHap 成功
Phase 2 代码替换（ItemRuntime 两处 + 删 utils/Totp.ets）
└─ 验证点：grep 零残留、assembleHap / assembleApp 成功
Phase 3 测试调整（删本地用例、加设备用例、两处 List.test.ets）
└─ 验证点：ohosTest target 编译成功；设备用例待用户在真机/模拟器执行
Phase 4 文档同步（MFA/AGENTS.md）
└─ 验证点：grep 断言
Phase 5 真机冒烟（用户执行，无设备时阻塞发布）
└─ 验证点：首页/详情/卡片/飞行模式四项通过
Phase 6 发布（用户操作：DevEco 打包 → AGC 提交）
```

**回滚**（纯前端，无数据/后端回滚）：

1. **正常回滚**：`git revert <本次 commit 区间>` → 重新用 DevEco/hvigor 打包；或手工把 `build-profile.json5` 两处 `useNormalizedOHMUrl` 改回 `false`、删除 `entry/oh-package.json5` 的依赖条目与 `entry/oh-package-lock.json5`、在根目录跑 `ohpm install`、恢复 `utils/Totp.ets` 与 `ItemRuntime` 两处改动；**测试面须同步回滚**：恢复 `entry/src/test/TotpCode.test.ets`、`test/List.test.ets` 恢复 `totpCodeTest` 注册、`ohosTest/ets/test/List.test.ets` 摘除 `totpDeviceTest`、删除 `entry/src/ohosTest/ets/test/TotpDevice.test.ets`（否则其 `import '@yansongda/otp'` 在依赖移除后会导致 ohosTest 编译失败）。
2. **紧急回滚**：应用市场版本回退（无后端依赖，旧版本可直接回滚上架）。

## 5. 风险与对策

| 风险 | 严重度 | 对策 |
|------|--------|------|
| `useNormalizedOHMUrl: true` 是**工程级构建开关**（改变编译产物里模块引用即 OHMUrl 的形式），运行期无法在本机验证（无设备） | **高** | 编译期与打包期已实测通过（含卡片 `pack.res` 链路）；把「真机冒烟（首页/详情/卡片/前后台切换/飞行模式）」列为发布前**强制人工门槛**；保留一键回滚路径；`true` 自 DevEco 5.0.3.800 起是新工程默认值，MFA 的 `false` 属遗留默认 |
| 字节码 HAR 的算法与后端 `build_noncompliant` 逐位不一致 | 中 | 库内自带 RFC 4226 Appendix D + RFC 6238 Appendix B 全量向量与设备侧 37 条实测；本工程再加 4 条设备侧用例；真机与微信端同窗对码 |
| 设备侧用例/本地用例在本工程不可跑（Local Test 结构性不可用、当前无设备） | 中 | 用例照旧落盘但**不阻塞构建**；真机执行项显式列入交付清单 |
| `ArkTS:WARN Property 'sourceMapsPath' not found in '@yansongda/otp'.` | 低 | 编译非阻断告警（实测）；影响仅调试符号映射。可选后续在 otp 仓库补 source map 元数据后重发包（本次不做） |
| 依赖版本漂移（registry 随时可能发布新版本——1.0.2 已于 2026-10-06 发布，本方案已随之升为 `^1.0.2`） | 低 | 约束取 `^1.0.2` 并提交 `entry/oh-package-lock.json5` 钉住解析结果；后续升级须显式重跑 `ohpm install` 并经评审（构建门禁 + 设备用例）后再入库 |
| 后人把 `useNormalizedOHMUrl` 改回 `false` 导致构建失败且难定位 | 低 | 写入 `MFA/AGENTS.md`：硬约束 + 报错码 `00306046` + 官方链接 |
| 依赖声明层级与既有 axios/dateformat（工程级）不一致造成困惑 | 低 | 在 `MFA/AGENTS.md` 明确「新增依赖声明在使用它的模块」的约定；既有依赖本次不迁移 |
| 删除自研白盒用例带走 base32 边界回归 | 低 | 原语由库内向量测试覆盖；设备侧用例覆盖端到端算码 |

## 6. 监控与可观测性

无上报通道（现状，本次不新建）。观测手段：

| 手段 | 内容 |
|------|------|
| `hilog.warn(LogDomain.MODELS, 'models/runtime', '端内算码失败，回退服务端: id=%{public}s', id)` | **原样保留**，仅 item id；禁止 secret（`%{public}s` 只放 id） |
| 后端指标 | 上线后 `POST /totp/detail` 调用量应与改造前持平；若显著上升 = 端内算码失败率上升（库异常/secret 异常的信号） |
| 构建期门禁 | `hvigorw assembleHap`（debug、ohosTest）与 `assembleApp`（release）必须 exit 0；`grep -rn "utils/Totp\|TotpCode" entry/src` 必须零命中 |
| 告警 | 无（无基础设施，不虚构指标） |

## 决策记录

| 编号 | 决策 | 结论 | 时间 |
|------|------|------|------|
| Q1 | 是否接受 `useNormalizedOHMUrl: false → true` | **接受**：官方硬约束（依赖字节码 HAR 必须为 true）+ 本机实测必需；替代方案（otp 库改发源码 HAR）需改另一仓库、重发版且未实测 | 2026-10-05 |
| Q2 | 依赖版本 | `^1.0.2`（2026-10-06 1.0.2 发布后由 `^1.0.1` 更新；与 1.0.1 无 `.ets` 差异，功能等价） | 2026-10-05（2026-10-06 修订） |
| Q3 | 是否新增本地冒烟用例 | **不新增**：官方明载 Local Test 不支持系统 API，库 barrel 顶层值导入 `internal/CryptoSource`（库内唯一 import kit 的文件） | 2026-10-05 |
| Q4 | 是否新增设备侧用例 | **新增** 4 条（真 crypto 黄金向量 + remaining + 默认时间戳） | 2026-10-05 |
| Q5 | 是否更新 `MFA/AGENTS.md` | **更新**（依赖清单 + `useNormalizedOHMUrl` 硬约束 + 声明层级 + 测试分层 + lint 说明 + 提交约束） | 2026-10-05 |
| Q6 | 是否动 `CHANGELOG.md` / 版本号 | **不动**（发布时按 release skill 统一记） | 2026-10-05 |
| Q7 | 依赖声明层级 | **entry 模块级**（官方推荐；实测最小 diff；根级亦可——表 1 中消费方=HAP 时为 `/`，但属「不建议」） | 2026-10-05 |
| Q8 | 倒计时是否改用库 `remaining()` | **不改**：现式与库语义同式等价，保留可避免「构造失败即倒计时停摆」的新耦合 | 2026-10-05 |

## 附录 A：本机实测证据（`/tmp` 复刻，未触碰仓库）

```bash
# 环境：DevEco Studio，hvigor 6.24.4，ohpm 6.1.2.285
#   DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
#   工程 targetSdkVersion/compatibleSdkVersion = 6.1.0(23)
cd /tmp/mfa-otp-spike3/MFA                       # rsync MFA（排除 build/oh_modules/.hvigor）
# ①　useNormalizedOHMUrl=false + 依赖 → BUILD FAILED
#    00306046 Specification Limit Violation
#    Bytecode HAR [@yansongda/otp] not supported when useNormalizedOHMUrl is not true.
# ②　entry 模块级声明依赖 + 根目录 ohpm install
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install
#    → 生成 entry/oh-package-lock.json5（606 B）；依赖落地 entry/oh_modules/@yansongda
# ③　assembleHap（debug）→ BUILD SUCCESSFUL in 4 s 589 ms（仅 sourceMapsPath 告警）
# ④　assembleApp（release）→ BUILD SUCCESSFUL in 4 s 701 ms
#    → build/outputs/default/MFA-default-signed.app 334 086 B、pack.res 105 415 B
# ⑤　assembleHap -p module=entry@ohosTest → BUILD SUCCESSFUL in 3 s 207 ms
#    → entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
```

**黄金向量**（RFC 4226 Appendix D / RFC 6238 Appendix B，secret `GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ`、SHA1、6 位、period=30）：

| T（epoch 秒） | 期望 6 位码 | 用途 |
|---------------|-------------|------|
| 59 | `287082` | 设备侧用例（RFC 4226 §D 向量） |
| 1234567890 | `005924` | 设备侧用例 |
| （`remaining(59000)`） | `1` | 倒计时对标 |

## 附录 B：调研依据（官方原文）

- 字节码 HAR 硬约束：「**依赖字节码HAR包时，该工程的build-profile.json5中的 useNormalizedOHMUrl 必须设置为true。**」——[构建HAR](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-build-har)
- `useNormalizedOHMUrl` 定义与一致性要求：「是否使用标准化的OHMUrl……**使用集成态HSP和字节码HAR需使用标准化的OHMUrl格式**」「若工程引用了HAR/HSP，**需确保工程的useNormalizedOHMUrl配置和HAR/HSP的useNormalizedOHMUrl配置保持一致，同时配置为true或false**」——[工程级build-profile.json5](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-build-profile-app#section13181758123312)
- 依赖声明层级：「**不建议在工程级oh-package.json5中配置生产依赖**」「**综上所述，我们建议您：当前模块使用到的依赖配置在本模块的oh-package.json5中。**」+「编译行为差异说明」表 1（消费方=编译 HAP 时，字节码HAR 三方包依赖配置在工程级 dependencies 为 `/`：编译和运行都正常）——[添加依赖项](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-dependencies)
- `types` 字段：「指定类型定义的文件名……**该字段优先于 main 字段**」——[oh-package.json5](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-oh-package-json5)
- 新工程默认值：「**升级到DevEco Studio NEXT Beta1（5.0.3.800）及以上版本，新建工程的工程级build-profile.json5的useNormalizedOHMUrl字段默认为true。**」——[DevEco Studio 5.0.0 Release 变更说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/ide-changelog-500-release)（与「字段缺省值为 `false`」不矛盾：前者指 IDE 新建工程模板写入 `true`）
- 本地测试边界：「**当前不支持测试C/C++方法及系统API。**」——[本地测试（Local Test）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-local-test)
- 库自身文档：`@yansongda/otp` v1.0.2 包内 `README-cn.md`（API 表、错误码表、本地/设备测试边界、RFC 符合性说明）；源码仓库 `~/000-Coding/ohos-otp`（`library/src/main/ets/TOTP.ets`、`internal/TimeStep.ets`、`internal/Base32.ets`、`CHANGELOG.md`）
- 同仓先例：`docs/huawei-totp-local-compute.md`（2026-09-30 端内算码改造方案，Q3 决策「直接接受 `no-unsafe-mac` 告警」）；`docs/evidence/huawei-totp-local-compute/*`（RFC 向量双实现验证、hvigor CLI 可用性实测）

## 修订记录

- 2026-10-05：初稿（对话内呈现并获批准）。含 5 项决策点 D1–D6。
- 2026-10-05：调研 agent（官方文档）回填后修订三处：**A** `useNormalizedOHMUrl: true` 从「实测必需」升级为「官方硬约束」（并逐条核对 `true` 的附带约束）；**B** 依赖声明层级由「根」改为 **entry 模块级**（官方推荐；补 Q7）；**C** 取消原「本地冒烟用例」（官方 Local Test 不支持系统 API），改为设备侧 ohosTest 用例。新增 Q8（倒计时不改用 `remaining()`）。
- 2026-10-05：Phase 0 spike 由调研期在本机 `/tmp` 完成并落盘证据（`docs/evidence/huawei-totp-switch-to-otp-lib/task-0-spike.md`），方案中所有「已验证」结论均以该证据为准。
- 2026-10-05：plan-reviewer 第 1 轮审查后修订：lint 收益改为可机械验证（删除无来源的「3 条」计数，补 MAC API 零引用等价断言）；行数更正 157/121；`period` 非整数行更正为「与自研行为相同」（自研 `Totp.ets:129-131` 本就校验）；barrel 表述精确化为 `internal/CryptoSource`（库内唯一 import kit 的文件）；§4 手工回滚补测试面步骤。
- 2026-10-05 / 2026-10-06：plan-reviewer 第 2 轮审查后修订：**B1** 采纳 `@yansongda/otp` **1.0.2**（registry 于 2026-10-06T09:03Z 发布 latest=1.0.2，原「未发布」前提过期）——依赖约束升为 `^1.0.2`，同步 §3.1 版本行/锁示例/§3.7/§5 风险表/Q2/附录 B；**m1** 行号更正为 `Totp.ets:129-131`；**m3** AGENTS.md 改动面补 lint 与提交约束。
- 2026-10-06：plan-reviewer 第 3 轮复审（0 BLOCKER / 0 MAJOR）后处理 4 条 MINOR：锁示例标注为「节选」并给出完整字段位置（§6）；附录 B 官方引文补全尾句「同时配置为true或false」（经官方页面镜像原文核实，plan 侧引文正确）；补录「5.0.3.800 起新建工程该字段默认为 true」的官方出处（DevEco Studio 5.0.0 Release 变更说明），消除该项「无法验证」状态。
