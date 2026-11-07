# 华为元服务 + 微信小程序：TOTP 加密备份导入 / 导出（跨端互通）

> **时间**：2026-11-07
> **作者**：Claude Opus 4.5 + yansongda
> **状态**：经过人工审核确认
> **范围**：`huawei/atomicservice/MFA`（ArkTS）+ `wechat/miniprogram/totp`（TS）+ 跨端格式规范；**零后端改动、零新增权限**
> **配套**：格式规范 `docs/specs/mfa-backup-v1.md`、测试向量 `docs/specs/mfa-backup-v1.vectors.json`、执行计划 `docs/implementation/2026-11-07-huawei-wechat-mfa-backup.md`

## 1. 背景与问题

**现状**（均已读源码验证）：

- 两端账号数据同构：华为 `types/Item.ets` 与微信 `types/totp.d.ts` 的 `config` 都含 `secret/period/digits/algorithm`，且都投影了后端 `config.tags`（服务端 `MAX_TAGS = 1`，`application-api/src/request/totp.rs:7`）与 `config.pinned`。
- **两端都没有任何导入 / 导出入口**；添加账号只能扫码或手输，一次一条（华为 `Index.ets:342-387`，微信 `pages/totp/index.ts`）。
- 后端只有单条 `POST /api/v1/totp/create`（URI 入参）+ `edit/tags` + `edit/pinned`（`application-api/src/routes.rs:67-75`）；`/totp/all` 已下发明文 `secret`（`request/totp.rs:37-43`）→ 导出无需额外接口；**无批量入口、无去重**。
- 平台能力不对称（已核验，见 §3.11）：元服务**不支持 Share Kit**、读剪贴板需受限权限；微信小程序**没有原生 AES/WebCrypto**，导出落盘只能走沙箱文件 + `wx.shareFileMessage` 或剪贴板。

**困境**：

1. 用户换 App / 换机只能逐条重建账号（20 条约 20 分钟），实际迁移门槛极高。
2. 明文导出（`otpauth://` 文本 / JSON）一旦落到剪贴板、聊天记录或截图，等于把全部 TOTP 密钥交给能看到它的人。
3. 同一用户可能同时用华为与微信两端，**任一端的备份必须能被另一端导入**，否则迁移链断裂。
4. 两端密码学能力不对称（native vs 纯 JS），必须靠**统一格式 + 统一参数 + 共享测试向量**来保证互通，而不是靠人工对齐。

**目标**（约束条件）：

- **零后端改动**、**零新增权限**（华为不增 `requestPermissions`；微信不增 scope）
- **端到端加密**：文件与剪贴板中只有密文；口令与派生密钥不上盘、不进日志
- **双向互通**：任一端产出的 `.mfa` 文件都能被另一端解密导入（同一口令）
- **保真**：`secret/period/digits/algorithm/tags/pinned` 全程保留
- **可演进**：`version` + `method` 是升级位，旧文件在新版本仍可导入
- **可一键回退**：入口与路由可单独下线；**加解密模块不撤**（否则用户已导出的文件将无法导入）

## 2. 整体方案

**核心思路**：**以 `docs/specs/mfa-backup-v1.md` 为唯一事实源，华为用系统原生 `cryptoFramework`、微信用零依赖纯 JS 实现同一套 PBKDF2-SHA256 + AES-256-GCM；两端用同一份测试向量（oracle = `node:crypto`）保证字节级一致；跨端交换主通道是加密文本的剪贴板，文件为次通道。**

```
        docs/specs/mfa-backup-v1.md  +  mfa-backup-v1.vectors.json (oracle: node:crypto)
                       │  唯一事实源（字段/参数/AAD/kcv/错误码/向量）
        ┌──────────────┴──────────────┐
        ▼                             ▼
 华为元服务（ArkTS）            微信小程序 totp（TS）
 ┌─────────────────────────┐   ┌─────────────────────────┐
 │ models/backup/Crypto    │   │ src/backup/aes-gcm.ts   │ 手写 AES-256+GCM
 │  Kdf/PBKDF2 (native)    │   │ src/backup/pbkdf2.ts    │ 复用 otp/internal
 │  Cipher/AES-GCM (native)│   │ src/backup/crypto.ts    │ kcv/加解密编排
 │  Mac/SHA256 (kcv)       │   │ src/backup/envelope.ts  │ 结构校验（纯函数）
 │ Envelope/Payload(纯函数) │   │ src/backup/payload.ts   │ 明文校验（纯函数）
 └───────────┬─────────────┘   └───────────┬─────────────┘
             │ 文件：DocumentViewPicker.save/select      │ 文件：writeFile + shareFileMessage / chooseMessageFile
             │ 剪贴板：Clipboard.copy / PasteButton      │ 剪贴板：setClipboardData / getClipboardData
             ▼                                          ▼
      ┌─────── 跨端交换：加密 JSON 文本（剪贴板为主通道）───────┐
      │ 华为导出 ──复制──▶ 微信「从剪贴板导入」                 │
      │ 微信导出 ──复制──▶ 华为「粘贴导入」（PasteButton 授权）  │
      │ 文件次通道：微信转发到「文件传输助手」→ 保存 → 华为 picker │
      └──────────────────────────────────────────────────────┘
```

**文件结构**（`[新]` 新建 / `[改]` 修改 / `[不动]` 明确不改）：

```
docs/specs/
├── mfa-backup-v1.md                               [新] 格式规范（唯一事实源）
├── mfa-backup-v1.vectors.json                     [新] 15 组共享向量（85 KiB）
└── gen-mfa-backup-vectors.mjs                     [新] 向量生成器（确定性、幂等、自校验）

huawei/atomicservice/MFA/entry/
├── module.json5                                   [不动] 不新增权限
├── resources/base/profile/routes.json              [改] 注册 "migrate"
├── resources/base/element/string.json             [改] +28 条文案
└── src/
    ├── main/ets/
    │   ├── App.ets                                [改] AppPagesName.MIGRATE
    │   ├── pages/Migrate.ets                       [新] 导入 / 导出页
    │   ├── pages/user/Detail.ets                   [改] 「更多」+1 条目
    │   ├── pages/Help.ets                          [改] +1 小节
    │   ├── pages/index/Index.ets                   [改] 空态 onImport 接线 + 1 行日志脱敏
    │   ├── components/index/EmptyState.ets         [改] +「从其它应用导入」次入口
    │   ├── models/backup/Spec.ets                   [新] 常量 / 错误码
    │   ├── models/backup/Envelope.ets               [新] 结构 + 严格校验 + 序列化
    │   ├── models/backup/Payload.ets                [新] 明文 payload 校验
    │   ├── models/backup/Crypto.ets                 [新] PBKDF2 / AES-GCM / kcv（native）
    │   ├── models/backup/Exporter.ets               [新] items → .mfa 文本
    │   ├── models/backup/Importer.ets               [新] 解密 → 计划 → 串行 create
    │   ├── utils/FileTransfer.ets                   [新] picker + fileIo 唯一 IO 入口
    │   └── utils/Clipboard.ets                      [改] +read()（仅 PasteButton 授权后）
    ├── test/{Envelope,Payload,ImportPlan}.test.ets  [新] 纯函数单测
    └── ohosTest/ets/test/BackupCrypto.test.ets      [新] 真机对齐共享向量

wechat/miniprogram/totp/
├── src/
│   ├── backup/{spec,envelope,payload,aes-gcm,pbkdf2,crypto,exporter,importer}.ts  [新] 8 个模块
│   ├── utils/backup-file.ts                        [新] writeFile / shareFileMessage / chooseMessageFile
│   ├── utils/clipboard.ts                          [改] +readText()
│   ├── pages/backup/index.{ts,wxml,scss,json}      [新] 页面
│   ├── pages/user/index.{ts,wxml}                  [改] 「更多」+1 条目
│   ├── pages/totp/index.{ts,wxml}                  [改] 空态 +「从其它应用导入」
│   ├── pages/help/index.{ts,wxml}                   [改] +1 节说明
│   └── app.json                                    [改] 注册 pages/backup/index
├── scripts/check-otp-invariants.mjs                [改] 扩展 src/backup 静态守卫（去注释）
├── tests/mfa/backup-*.test.ts                      [新] 向量 / 篡改 / 口令错误 / 编排
└── AGENTS.md                                       [改] 记录 src/backup 例外与不变量
```

## 3. 详细设计

> 格式与密码学细节以 `docs/specs/mfa-backup-v1.md` 为准（本文不重复字段表，只说明实现侧分工与决策理由）。

### 3.1 文件格式（用户确认版）

`{"format":"mfa","version":1,"method":"PBKDF2-SHA256/AES-256-GCM","key":{…},"data":"…","meta":{…}}`，后缀 **`.mfa`**（用户指定）。

- `key` 是**参数容器**（`iterations/salt/iv/tag/kcv`），**不含真实密钥**——若把密钥写进文件，加密等价于明文。
- `meta` 只用于导入前提示与排障，不参与安全判定（`count` 与解密结果不一致即 `E_PAYLOAD`）。

### 3.2 密码学实现分工

| 环节 | 华为（ArkTS，native） | 微信（TS，纯 JS） |
|---|---|---|
| PBKDF2 | `createKdf('PBKDF2\|SHA256')` + `PBKDF2Spec`（`@atomicservice [since 12]`，SDK 已核验） | 复用 `src/otp/internal/sha256.ts` + `hmac.ts` 迭代实现 |
| AES-256-GCM | `createCipher('AES256\|GCM\|NoPadding')` + `GcmParamsSpec{iv,aad,authTag}`；`doFinal` 结果末 16B 为 tag，需拆分 | **手写** AES-256 分组 + GHASH/CTR（约 250 行，`Uint32` 分肢，**禁 BigInt**，与 `src/otp` 风格一致） |
| kcv | `createMac('SHA256')` | 复用 `hmac.ts` |
| 随机 | `createRandom().generateRandomSync(16/12)` | `wx.getRandomValues({length})`（2.15.0+，ArrayBuffer） |
| base64 | `util.Base64Helper` | `wx.arrayBufferToBase64` + 自写解码（小程序无 `atob`） |
| UTF-8 | `util.TextEncoder` / `PBKDF2Spec` 字符串形态（官方注明 UTF-8） | 自写 `utf8ToBytes`（`TextEncoder` 在小程序无官方支持） |

**为什么微信端自研而不引库**：`wechat/miniprogram/totp/AGENTS.md` 明确「不重新引入任何运行时密码学依赖」，且 `@noble/ciphers` v2 为纯 ESM，`miniprogram_npm` 的 CJS 构建路径存在不确定性（社区已有失败案例）。自研 + 共享向量可把风险压到「向量全绿」这一可验证条件上。

**为什么选 AES-256-GCM 而不是 CTR+HMAC**：AEAD 单原语，华为侧天然支持；GCM 的额外实现面（GHASH）由 15 组向量（含 1/15/16/17 字节边界）覆盖。

### 3.3 口令与密钥派生

- 规范化：`trim()` → `NFC` → UTF-8（两端逐字一致；向量 case-03/case-04 专门覆盖中文与 NFD）。**运行时不支持 `String.prototype.normalize` 时两端都必须 fail-closed**（提示"当前系统不支持口令规范化"并中止），禁止降级为「不归一化」（会造成一端归一化、一端不归一化 → 派生不同密钥 → 跨端永久解不开）。
- 导出端强度校验：≥ **8 个 Unicode 码点**（`Array.from(s).length`，与两端 JS `.length` 的 UTF-16 口径区分开）+ 拒绝 10 个常见弱口令（两端各自常量表，文案一致）。
- 迭代数：默认 `100000`，**写入文件**；导入以文件为准（`10000..500000`）。
- **派生必须是分片异步**：微信端小程序 JS 单线程，同步 100k 迭代（实测本机 bun ≈386ms，低端手机按 5–15 倍折算 2–6s）会冻结 UI 与取消按钮；实现按每 ~2000 次迭代 `await` 让出事件循环并向 UI 回报进度（华为端 `Kdf.generateSecret` 本身是 Promise，UI 不阻塞）。

### 3.4 传输通道

| 组合 | 主通道 | 次通道 |
|---|---|---|
| 华为导出 → 微信导入 | 剪贴板（华为复制 → 微信粘贴） | 华为保存 `.mfa` → 文件管理「发送到微信」→ 微信「从聊天选择文件」 |
| 微信导出 → 华为导入 | 剪贴板（微信复制 → 华为 PasteButton 粘贴） | 微信 `shareFileMessage` → 文件传输助手 → 保存 → 华为 picker 选择 |
| 同端往返 | 剪贴板 | 文件 |

- 华为导出文件：`DocumentViewPicker.save({newFileNames:['mfa-backup-YYYYMMDD-HHmm.mfa'], fileSuffixChoices:['MFA 备份|.mfa']})` + `fileIo` 写入用户选定位置（**不写沙箱**）。
- 华为导入文件：`DocumentViewPicker.select()`（**不设后缀过滤**，内容嗅探）。
- 微信导出文件：`writeFile(USER_DATA_PATH)` + `wx.shareFileMessage`（**必须用户点击**，官方限制）。
- 微信导入文件：`wx.chooseMessageFile({count:1,type:'file'})`（不传 `extension`）+ `readFile`。
- 剪贴板：华为写 `Clipboard.copy`、读 `PasteButton` 授权后 `getData`（**不申请受限权限 `READ_PASTEBOARD`**）；微信 `set/getClipboardData`。

### 3.5 导入执行（两端同构）

```
解密 → 计划（accepted / duplicates / invalid）→ 用户确认 → 串行 create(uri)
     → 校正：响应 issuer/username 与目标不一致时 editIssuer/editUsername
     → tags 非空则 editTags；pinned 为 true 则 editPinned
     → 逐条进度 → 结束汇总 → 刷新列表 + 卡片/缓存同步
```

- **URI 重建的坑（已读源码核实）**：后端唯一写入入口是 `otpauth://` URI，而 totp-rs `split_label` 会在 label 中**第一个裸 `:` 或 `%3A`** 处切分 issuer/account，query `issuer` 与 label 前缀不一致还会报 `IssuerMismatch`（→ `2009`）。因此 `issuer` 含冒号、或 `issuer` 为空而 `username` 含冒号时，直接用目标值构造 URI 会报错甚至**静默串位**。规范 §6.2 定义了统一的重建策略：用安全占位符 `"__mfa__"` 建号，再按创建响应比对并 `editIssuer`/`editUsername` 校正（这两个接口接受 `:` 与空串，`application-database/src/tool/totp.rs:185-201` 直接写库）。

- **幂等**：去重键 `secret|issuer|username`（两端本地快照都持有 `secret`）；重复导入同一包全部命中 `duplicates`。
- **部分失败**：不中断；重跑自动跳过已成功项。
- **取消**：已成功条目保留，汇总标注「未执行 N 条」。
- 条数上限 500；剪贴板通道建议 ≤50 条（超限强制文件通道）。

### 3.6 页面与入口

- 华为：`pages/Migrate.ets`（路由 `migrate`），两张卡（导出 / 导入）；入口 ①「我的 → 更多 → 导入 / 导出」②**首页空态次入口「从其它应用导入」**（`EmptyState` 新增 `onImport`，`Index` push）。
- 微信：`pages/backup/index`，结构同构；入口 ①「我的 → 更多 → 导入 / 导出」②**首页空态次链接「从其它应用导入」**（`pages/totp/index.wxml` 的 `empty-help` 区）。
- 口令交互：导出输入 + 确认；导入输入一次；**不记忆口令**，页面 `onHidden` 清空。

### 3.7 安全设计

| 项 | 规则 |
|---|---|
| 导出前 | 确认弹窗（含条数与"忘记口令无法恢复"）→ 应用锁验证。**映射**：`SUCCESS` 放行；`NO_CREDENTIAL` 放行（系统已降级关闭应用锁）；**`SKIPPED` 拒绝**（它表示"上一次验证结束 3 秒内"或"已有验证在飞"；若放行，拿到已解锁手机的人可先点取消、再在 3 秒内点导出，从而绕过认证）→ 提示"身份验证未完成，请 3 秒后重试"；`CANCELED`/`FAILED` 中止 |
| 日志 | 华为 `%{private}s`（顺带修 `Index.ets:361` 扫码结果既有泄漏）；微信 `logger` 只记事件与计数 |
| 持久化 | 口令/密钥/明文/密文都不写 preferences / storage |
| 输入信任 | 导入文件按不可信输入处理（先结构校验再要求口令） |
| 通道风险 | 剪贴板提示「导入完成后清理」；不提供口令找回 |

### 3.8 兼容性与降级

| 失败 | 降级 |
|---|---|
| 华为 picker 不可用 | 剪贴板通道 |
| 华为 `PasteButton` 授权失败（样式约束） | `TextArea` 手贴 |
| 微信 `shareFileMessage` / `chooseMessageFile` 不可用 | 剪贴板通道 |
| 未知 `version` / `method` | 明确报错（`E_VERSION` / `E_METHOD`），不尝试解密 |
| 旧数据缺 `secret` | 导出跳过并计数 |

### 3.9 测试策略

- 纯函数单测：华为 `entry/src/test`（本地可跑）、微信 `tests/mfa`（`bun test`，CI 可跑）。
- 密码学：共用 `docs/specs/mfa-backup-v1.vectors.json`；华为放 `ohosTest`（真机/模拟器，Local Test 不支持系统 API）；微信放 `tests/mfa`。
- 端到端：真机 4 组合 × {正确口令、错误口令、篡改 1 字节、超限包}。
- 向量生成器自带解密回环自校验，保证 oracle 自身正确。

### 3.10 接口对接（零新增）

`POST /api/v1/totp/create`：`{"uri":"otpauth://totp/<issuer>:<account>?secret=…&issuer=…&algorithm=…"}` → 返回单条 `DetailResponse`（含 `config.secret`）。
- 校验：小写 `otpauth://totp/` 前缀（`request/totp.rs:86`）、`digits ∈ 6..8`、`period ≠ 0`（`service/totp.rs:63`）；**不查重、不收 tags/pinned** → 导入后按需追加 `edit/tags`、`edit/pinned`。
- 失败码：`2009/2012`（URI 非法）、`2008`（id 未找到）、`2022`（标签非法）。

### 3.11 平台能力证据

| 能力 | 结论 | 证据强度 |
|---|---|---|
| 元服务 `DocumentViewPicker.select/save` | 支持 API 12+ | 本机 SDK `@ohos.file.picker.d.ts` 逐方法 `@atomicservice [since 12]` + 官方 API 参考 |
| 元服务 `fs.openSync/writeSync/readSync` | 支持 API 11+；`readText` 仅沙箱路径 | SDK d.ts |
| 元服务 `pasteboard.setData` | 支持 API 11+ | SDK d.ts |
| 元服务读剪贴板 | 需受限权限 `READ_PASTEBOARD`（ACL + 审核）→ **改用 PasteButton** | 官方权限文档；`paste_button.d.ts` `@atomicservice [since 11]` |
| 元服务 `ShareKit/systemShare` | **不支持** | 官方 FAQ 原文 |
| 元服务 `cryptoFramework`（Kdf/Cipher/Mac/Random） | 支持 API 12+ | SDK d.ts `@atomicservice [since 12]` |
| 微信原生 AES/WebCrypto | **无**（仅 `wx.getRandomValues` 2.15.0+） | 官方文档（无 createCipheriv / 无 WebCrypto 声明） |
| 微信 `shareFileMessage` / `chooseMessageFile` | 2.16.1 / 2.5.0；share 需用户点击 | 官方 API 文档 |
| 微信 `set/getClipboardData` | 1.1.0+，无 scope；**长度上限官方未承诺** | 官方 API 文档 |
| 版本门槛 | 华为 `compatibleSdkVersion 6.1.0(23)` ≥ 12 ✔；微信 `libVersion 3.7.12` ≥ 2.16.1 ✔ | 工程配置 |

## 4. 推进策略

```
P0 契约（已完成）：规范 + 向量 + exampleEnvelope（docs/specs/）
P1 微信 crypto（可先做，CI 可验）：
   spec/envelope/payload/aes-gcm/pbkdf2/crypto + tests（全向量断言）
   → 验证：bun run test 全绿；篡改/口令错误返回预期错误码
P2 微信 UI 与通道：exporter/importer + backup-file + 页面 + 两个入口
   → 验证：真机 导出→清空→导入 闭环
P3 华为（依赖 P0 向量）：Spec/Envelope/Payload → Crypto(ohosTest 对齐) → Exporter/Importer → FileTransfer/Clipboard/页面/入口
   → 验证：ohosTest 向量全绿；真机 picker / PasteButton 回归
P4 跨端互测 + 文档收尾：4 组合矩阵 → Help / AGENTS / CHANGELOG
```

**回滚**：入口与路由可单独下线（华为删 `routes.json` 条目 + 入口 + 空态入口；微信删 `app.json` 页面 + 两个入口），**加解密模块保留**；无后端与数据迁移。若必须彻底撤除，需先发布"仅保留导入"的过渡版本，避免用户已导出的 `.mfa` 文件永久不可用。

## 5. 风险与对策

| # | 风险 | 严重度 | 对策 |
|---|---|---|---|
| R1 | 微信手写 AES-GCM 有隐蔽缺陷（跨端解不开/静默错） | 高 | 15 组共享向量（含 1/15/16/17 字节边界、中文/emoji、100 条规模）+ 真机 4 组合互测 + 向量生成器自校验 |
| R2 | 纯 JS PBKDF2 100k 迭代在老设备慢（实测 bun 386ms，低端手机折算 2–6s；同步实现还会冻结 UI） | 中 | **分片异步派生**（每 ~2000 次迭代让出事件循环，进度可显示、可取消）；P1 记录实测耗时；必要时把默认降到 60000（写入文件，旧文件仍可读）；`MAX_ITERATIONS` 保持 500000 但导入超默认值时提示可能耗时 |
| R3 | 微信剪贴板长度无官方承诺，大包可能截断 | 中 | 剪贴板通道限 ≤50 条 / ≤64 KiB；超限强制文件通道；导入端截断即 `E_FORMAT` |
| R4 | 华为 `PasteButton` 安全控件样式违规 → 授权失败（error 2） | 中 | 默认 options + 官方约束；`TextArea` 手贴兜底；真机回归 |
| R5 | 华为 picker 在元服务真机行为与文档不符 | 中 | 剪贴板通道兜底；发布前真机 spike |
| R6 | 口令规范化（空格/NFC）不一致导致互通失败 | 中 | 规范固定 `trim+NFC` + 码点长度口径；向量 case-03/04 专测；双端断言同一 keyB64；`normalize` 不可用时两端都 fail-closed |
| R16 | `issuer`/`username` 含冒号时 URI 重建失败或静默串位（totp-rs `split_label` 在首个 `:`/`%3A` 切分） | 中 | 规范 §6.2 统一重建策略（`"__mfa__"` 占位 + 按响应 `editIssuer`/`editUsername` 校正）；T6/T7/T8 各加冒号保真用例 |
| R17 | `docs/specs/` 未入库会让微信 CI（全新 checkout 跑 `bun run test`）读到不存在的向量文件而确定性变红 | 中 | T0 显式提交 `docs/specs` 三件套 + 技术设计文档；T9/F4 用 `git ls-files docs/specs` 复核 |
| R7 | 用户忘记口令 → 备份永久不可用 | 高 | 导出前显式警告 + 二次输入确认；无重置路径；帮助页说明 |
| R8 | 明文外泄（剪贴板、聊天文件、截图） | 高 | 只导出密文；剪贴板提示清理；帮助页说明 |
| R9 | 导入半程失败/取消 | 中 | 串行 + 逐条计数 + 汇总；重跑跳过重复 |
| R10 | 后端无批量接口（N 条 × 1–3 请求） | 中 | 单包 ≤500；进度可见 + 可取消；后续评估 `POST /totp/import` |
| R11 | `tags/pinned` 语义差异（华为单标签） | 低 | payload 保留数组，导入按各端规则截断（华为取首个） |
| R12 | 版本/算法演进破坏旧包 | 中 | `version` → `method` 分派；未知即报错，不静默尝试 |
| R13 | 密钥进日志 | 中（既有 1 处泄漏） | 规范 S2 + 华为 `%{private}s`（顺带修 `Index.ets:361`）+ 微信 logger 禁打 + 静态 grep 校验 |
| R14 | `meta` 被篡改（如改成 999 条） | 低 | `meta` 不参与安全判定；解密后 `count` 必须与 `items.length` 相等 |
| R15 | 元服务上架审核问询 | 低 | 无新增权限/隐私字段；文件能力为用户主动触发 |

## 6. 监控与可观测性

仅本地日志（无埋点外发），统一「事件 + 计数 + 错误码」，**不含口令/密钥/密文/明文**：

```json
{ "event":"backup_export","channel":"file|clipboard","count":12,"skipped":1,"iterations":100000,"elapsedMs":820 }
{ "event":"backup_parse","channel":"clipboard|file","accepted":8,"duplicates":2,"invalid":1,"count":12 }
{ "event":"backup_import","done":8,"failed":0,"canceled":false,"elapsedMs":4210,"withTags":3,"withPinned":1 }
{ "event":"backup_error","code":"E_PASSWORD","stage":"derive" }
```

| 指标 | 计算 | 判定 |
|---|---|---|
| 导入成功率 | `done/(done+failed)` | 真机抽样 < 95% → 排查失败 `code` |
| 派生耗时 | `elapsedMs`（stage=derive） | > 3000ms → 评估下调默认迭代数 |
| 错误分布 | 按 `code` 计数 | `E_CORRUPT` 非 0 → 立即排查编解码一致性 |
| 条数一致性 | `meta.count == items.length` 且 `count + skipped == 本地账号总数` | 不等即缺陷 |

## 7. 已确认决策（原待确认项）

| # | 决策 | 结论 |
|---|---|---|
| 1 | `key` 字段语义 | **参数容器（对象）**，不含真实密钥 |
| 2 | 微信端范围 | 只做 `wechat/miniprogram/totp`；`yansongda` 后续复用同模块 |
| 3 | 微信加密实现 | **零依赖手写**（复用 `src/otp/internal` 原语） |
| 4 | 算法组合 | **PBKDF2-SHA256 + AES-256-GCM** |
| 5 | 明文 `otpauth` 导出 | **不做**（仅加密包） |
| 6 | 导出前应用锁验证 | **做** |
| 7 | 首页空态入口 | **做**（华为 + 微信各一处） |
| 8 | 文件后缀 | **`.mfa`**（导入端内容嗅探，不依赖后缀） |

### 7.1 独立审查后的修正决策（2026-11-07 第二轮）

| # | 事项 | 结论 |
|---|---|---|
| 9 | 应用锁门禁的 `SKIPPED` | **拒绝**（原「放行」被审查认定为 3 秒窗口绕过） |
| 10 | 冒号导致的 URI 串位 | 采用规范 §6.2「占位建号 + edit 校正」，不做字符集封禁 |
| 11 | 微信 PBKDF2 | 改**分片异步**（可进度、可取消），保留同步内核仅供单测 |
| 12 | `docs/specs` 入库 | 由 T0 提交；CI 依赖该文件 |
| 13 | evidence / 执行计划 | 依仓库 `.gitignore` **只留本地、不入库** |
| 14 | 静态守卫 | 扩展现有 `check-otp-invariants.mjs`（去注释），不新增裸 `grep` |

## 8. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-07 | 初版；含 `.mfa` 后缀与空态入口两项调整 |
| 2026-11-07 | 第二轮（独立审查）：修正 exampleEnvelope 指向、`SKIPPED` 门禁、冒号重建策略、PBKDF2 分片异步、docs/specs 入库与 evidence 口径 |
