# MFA 加密备份格式规范 v1（`mfa-backup`）

> **时间**：2026-11-07（初版）；2026-11-08（预发布修订：`meta` 纳入 AAD、`createdAt` 带时区）
> **作者**：Claude Opus 4.5 + yansongda
> **状态**：经过人工审核确认
> **适用实现**：华为元服务 `huawei/atomicservice/MFA`（ArkTS）、微信小程序 `wechat/miniprogram/totp`（TypeScript）
> **唯一事实源**：两端实现不得偏离本规范；正式发布前允许预发布修订（见 §10.1），发布后任何语义变更必须升 `version` 或新增 `method`
> **配套**：向量文件 `docs/specs/mfa-backup-v1.vectors.json`、生成脚本 `docs/specs/gen-mfa-backup-vectors.mjs`

## 0. 摘要

一个 `.mfa` 文件 = **JSON 信封**（`format/version/method/key/data/meta`）+ **密文**（`data`）。
密钥由用户口令经 **PBKDF2-HMAC-SHA256** 派生；密文由 **AES-256-GCM** 产生，GCM 认证标签（tag）单独存放；口令是否正确由 **kcv**（HMAC 前 8 字节）判定，从而把「口令错误」与「文件损坏」区分开。`meta` 为明文，但**纳入 AAD 认证**（改任一字段都会令 tag 校验失败）；`meta.createdAt` 带时区偏移，导入端按用户本地时区显示。

## 1. 范围

- **本规范定义**：文件内容格式、密码学参数、校验规则、错误码、测试向量。
- **本规范不定义**：文件如何传输（各端自选：文件选择器 / 剪贴板 / 聊天文件）、UI 交互、口令强度提示文案、服务端接口。

## 2. 术语

| 术语 | 含义 |
|---|---|
| 信封 envelope | `.mfa` 文件的顶层 JSON 对象 |
| 明文 payload | 解密后得到的 JSON（含 `items` 数组） |
| 口令 password | 用户输入、**不写入文件**的字符串 |
| 派生密钥 key | PBKDF2 输出的 32 字节，仅存在于内存 |
| kcv | Key Check Value，用于快速判定口令是否正确 |
| AAD | Additional Authenticated Data：参与认证但不加密的数据（此处 = AAD 前缀 + meta） |

## 3. 信封结构

```json
{
  "format": "mfa",
  "version": 1,
  "method": "PBKDF2-SHA256/AES-256-GCM",
  "key": {
    "iterations": 10000,
    "salt": "GdUxb0sazJpTZcEeCISwig==",
    "iv": "IacMfU+gLiS/sa+E",
    "tag": "f/ASQJdUhkS3HjNszLLVLA==",
    "kcv": "b8ZuT0hzVh0="
  },
  "data": "8dIOT6u+bprXveHHHwmwKIvpCyOjN411kpGxvQjXlrtJbjR0PdXtrwGSi7miYJYNB8nMXUJvIiFrDB1JxDHLcs6yR3tm55jO9VdS7IFCAVLiGZOvyY8tkjtLZnZSvReesy4i2Ht1662Zy4UWs2oe8kp+zaZfMXqEj1kE7S8o0mb/lA8zAfDz/mZ9Ts6Ju1Rw4D0kOPqHW6wZkrwi+/fp/zKjjfIC9WScKl0=",
  "meta": { "count": 1, "createdAt": "2026-11-07T08:00:00.000+08:00", "source": "huawei", "app": "1.9.0" }
}
```

> 上面示例取自向量 `case-12`（口令 `12345678`，迭代 10000），可端到端解密为 1 条 GitHub 账号。

### 3.1 字段定义与校验

| 字段 | 类型 | 必填 | 约束 | 违反时的错误码 |
|---|---|---|---|---|
| `format` | string | 是 | 严格等于 `"mfa"` | `E_FORMAT` |
| `version` | integer | 是 | 恰为 `1`；整数且 `> 1` → `E_VERSION`；非整数或 `< 1` → `E_STRUCTURE` | `E_VERSION` / `E_STRUCTURE` |
| `method` | string | 是 | 见 §4.6 注册表，v1 仅 `"PBKDF2-SHA256/AES-256-GCM"` | `E_METHOD` |
| `key.iterations` | integer | 是 | `10000 ≤ n ≤ 500000` | `E_STRUCTURE` |
| `key.salt` | base64 | 是 | 解码后 **16 字节** | `E_STRUCTURE` |
| `key.iv` | base64 | 是 | 解码后 **12 字节** | `E_STRUCTURE` |
| `key.tag` | base64 | 是 | 解码后 **16 字节** | `E_STRUCTURE` |
| `key.kcv` | base64 | 是 | 解码后 **8 字节** | `E_STRUCTURE` |
| `data` | base64 | 是 | 解码后 1 字节 ~ 1 MiB | `E_STRUCTURE` |
| `meta` | object | 是 | 见 §3.2 | `E_STRUCTURE` |
| `meta.count` | integer | 是 | `0 ≤ n ≤ 500`（必须等于解密后 `items.length`；参与 AAD） | `E_STRUCTURE`（解密后不等 → `E_PAYLOAD`） |
| `meta.createdAt` | string | 是 | RFC 3339 / ISO 8601 **带时区偏移**：`YYYY-MM-DDTHH:mm:ss.SSS±HH:mm`；导入端另接受 `Z` 与 0~3 位毫秒。见 §7 | `E_STRUCTURE` |
| `meta.source` | string | 是 | `"huawei"` 或 `"wechat"`；参与 AAD | `E_STRUCTURE` |
| `meta.app` | string | 是 | 导出端版本号：**可打印 ASCII**（0x20~0x7E，不含 `"` 与 `\\`），≤ 32 字符；参与 AAD | `E_STRUCTURE` |

**禁止出现**：`password` / 真实密钥 / 任何形似密钥的字段。`key` 只承载「派生与解密参数」。

**未知字段**：实现方必须**忽略**（前向兼容：新版可能新增可选字段），但不得因此改变上述校验。

### 3.2 `meta` 的定位

`meta` 是**明文元信息**：写进文件、不加密，但**纳入 AAD 认证**（§4.2），因此不可篡改。它用于导入前的 UI 提示（“该备份包含 N 条账号”）与排障；`createdAt` 被认证后，导入端可以放心按用户本地时区显示。`meta.count` 与解密结果不一致仍按 `E_PAYLOAD` 拒绝导入（双保险）。

## 4. 密码学参数

### 4.1 参数表

| 项 | 值 | 备注 |
|---|---|---|
| 口令规范化 | `trim()` → Unicode **NFC** → UTF-8 编码字节 | 见 §5 |
| KDF | **PBKDF2-HMAC-SHA256** | 迭代数从 `key.iterations` 读取 |
| 派生长度 | **32 字节** | AES-256 密钥 |
| 对称加密 | **AES-256-GCM** | AEAD |
| IV | **12 字节**（CSPRNG 生成） | 每次导出重新生成 |
| Tag | **16 字节** | 与密文**分开存放** |
| salt | **16 字节**（CSPRNG 生成） | 每次导出重新生成 |
| AAD | `"mfa\|1\|" + method + "\|" + canonicalMetaJson(meta)` 的 UTF-8 字节 | 绑定 `version`/`method` 与 `meta`，防头部/元信息篡改与算法降级 |
| kcv | `HMAC-SHA256(key, "mfa-kcv\|1")` 的**前 8 字节** | 判定口令正确性 |
| base64 | 标准字母表 + padding（**禁用 base64url**） | 见 §7 |

### 4.2 常量

```
AAD_PREFIX = "mfa|1|PBKDF2-SHA256/AES-256-GCM|"   # "mfa|" + version + "|" + method + "|"
AAD        = AAD_PREFIX + canonicalMetaJson(meta)
KCV        = "mfa-kcv|1"

canonicalMetaJson(meta) = JSON.stringify({ count, createdAt, source, app })
# 字段顺序固定、紧凑（无空格）；例：
# {"count":1,"createdAt":"2026-11-07T08:00:00.000+08:00","source":"huawei","app":"1.9.0"}
```

- **为何用 canonical JSON 而不是 `|` 平铺字段**：JSON 自描述，`app` 等字段含 `|` 也不会产生拼接歧义。
- **为何要求 `app` 为可打印 ASCII**：canonical JSON 中永不出现 `\"` / `\\` / `\uXXXX` 转义，消除两端 JSON 转义差异。
- **AAD 用的是文件原文**：解密端不得重新解析/规范化 `createdAt`（同一时刻的不同时区写法是不同 AAD）。
- `version` / `method` 取自**信封字段**（加密时即常量），使 AAD 真正绑定头部。

后续 `version` 升级时 AAD 与 KCV 标签**必须同步变更**（例如 v2 → `mfa|2|<method>`），避免跨版本混淆。

### 4.3 加密流程

```text
password_bytes = utf8(nfc(trim(password)))
salt  = cspRng(16); iv = cspRng(12)
key   = PBKDF2_HMAC_SHA256(password_bytes, salt, iterations, dkLen=32)
meta  = { count:len(items), createdAt:localIsoWithOffset(), source:"huawei|wechat", app:appVersion }
aad   = "mfa|1|" + METHOD + "|" + canonicalMetaJson(meta)   # UTF-8, 见 §4.2
body  = compactJson({ v: 1, items: [...] })              # UTF-8, 见 §6/§7
ct,tag= AES_256_GCM_encrypt(key, iv, aad, body)          # tag = 16B
kcv   = HMAC_SHA256(key, KCV)[0..8]
envelope = { format:"mfa", version:1, method:METHOD,
             key:{ iterations, salt:b64(salt), iv:b64(iv), tag:b64(tag), kcv:b64(kcv) },
             data: b64(ct),
             meta }
```

### 4.4 解密流程（含判定顺序）

```text
1  JSON.parse → 校验 format → version → method（顺序不可调换，见 §8）
2  校验 key/meta/data 结构与长度（§3.1）
3  key = PBKDF2(password_bytes, salt, key.iterations, 32)
4  if HMAC_SHA256(key, KCV)[0..8] != key.kcv   → E_PASSWORD      # 先判 kcv
5  body = AES_256_GCM_decrypt(key, iv, AAD(envelope.version, method, meta), ct, tag)
       失败（tag 校验不过）                     → E_CORRUPT      # 再判 GCM（含 meta 篡改）
6  JSON.parse(body) → 校验 payload（§6）
7  if payload.items.length != meta.count       → E_PAYLOAD
```

**为什么 kcv 必须先于 GCM**：GCM 失败无法区分「口令错」与「文件被改」，会造成误导性提示；kcv 只依赖密钥，能先判定口令。

### 4.5 `iterations` 作为数据

- 导出端写入**实际使用**的迭代数（v1 默认 `100000`）。
- 导入端**以文件为准**，仅在 `10000..500000` 区间内接受。
- 允许未来提高默认值（旧文件仍可解密），无需升 `version`。

### 4.6 `method` 注册表

| method | 状态 | 说明 |
|---|---|---|
| `PBKDF2-SHA256/AES-256-GCM` | ✅ v1 唯一 | 本文档所定义 |

新增 method 必须：① 在本规范登记；② 升 `version`；③ 两端同时发布导入能力后再允许导出。

## 5. 口令规范化（跨端一致的关键）

```text
normalized = password.trim().normalize("NFC")
bytes      = UTF8(normalized)
```

| 规则 | 原因 |
|---|---|
| `trim` | 用户在不同键盘/平台输入时易产生不可见首尾空格，不 trim 会导致「同一口令不同密钥」 |
| `NFC` | 中文/带音标字符可能存在 NFC/NFD 两种编码，不同端输入法产出不同 → 不归一化会互解失败 |
| 不做其他处理 | 不截断、不转小写、不去除标点 |

**导出端强度要求**（导入端不校验）：

- 长度 ≥ 8 个 **Unicode 码点**（用 `Array.from(s).length` 计，避免两端分别用 UTF-16 `.length` 与码点计数得出不同结论）。
- 不与该端 10 个最常见弱口令之一相同（实现方定义常量表，提示"口令过弱"）。

**运行时不支持 `String.prototype.normalize` 时（fail-closed）**：必须**拒绝本次导出与导入**并提示"当前系统不支持口令规范化"，**不得**静默跳过归一化——否则一端归一化、另一端不归一化会派生出不同密钥，用户将无法跨端解密，且失败不可预期。

**口令遗忘不可恢复**：规范不提供任何重置/后门；实现方必须在导出前显式告知。

## 6. 明文 payload

```json
{"v":1,"items":[
  {"issuer":"GitHub","username":"alice@example.com","secret":"JBSWY3DPEHPK3PXP",
   "period":30,"digits":6,"algorithm":"SHA1","tags":["工作"],"pinned":true}
]}
```

| 字段 | 类型 | 必填 | 约束 | 违反时的处理 |
|---|---|---|---|---|
| `v` | integer | 是 | `1` | payload 整体 `E_PAYLOAD` |
| `items` | array | 是 | 长度 `0..500` | `E_PAYLOAD` |
| `items[].issuer` | string | 是 | 0~128 字符（允许空串） | 该条 `invalid` |
| `items[].username` | string | 是 | 0~128 字符（允许空串） | 该条 `invalid` |
| `items[].secret` | string | 是 | 剔除空格与 `-` 后必须为合法 Base32（尾长 ∈ {0,2,4,5,7}，填充位为 0） | 该条 `invalid` |
| `items[].period` | integer | 是 | `1..86400`（后端拒绝 0） | 该条 `invalid` |
| `items[].digits` | integer | 是 | `6..8`；越界时回落 `6` | 回落 |
| `items[].algorithm` | string | 是 | `SHA1/SHA256/SHA512`；其他值回落 `SHA1` | 回落 |
| `items[].tags` | string[] | 否 | 缺省 `[]`；每项 1~32 字符 | 超限项丢弃；华为端最多保留 **1** 个 |
| `items[].pinned` | boolean | 否 | 缺省 `false` | — |

- 不导出 `id` / `sort` / `code` / 图标 / 备注：这些属于服务端状态或端内态，导入必然是「新建账号」。

### 6.1 去重与「缺 secret 的本地条目」

- 去重键：`secret|issuer|username`（`secret` 先剔除空格与 `-`、转大写、去 padding；`issuer`/`username` 用原值）。
- 批内去重 + 与本地已有条目比对。
- 本地已有条目若**缺 `secret`**（旧数据/历史响应），**不参与去重比较**（无法判定是否同一密钥）：该条可能被重复导入，实现方不计入 `duplicates`，也不因此拒绝导入。

### 6.2 导入重建策略（URI 无法承载的字段）

后端唯一写入入口是 `POST /api/v1/totp/create`（`otpauth://` URI）。totp-rs 6.0.0 的 `split_label`（`~/.cargo/registry/.../totp-rs-6.0.0/src/url.rs:224-242`）在 **label 路径中第一个裸 `:` 或 `%3A`** 处切分 issuer/account；且 query `issuer` 与 label 前缀不一致会报 `IssuerMismatch`（后端映射为 `2009`）。已读源码核实：

| 情况 | 直接 create 的结果 | 结论 |
|---|---|---|
| issuer 不含 `:`、username 含 `:` | label `issuer:a%3Ab` → 首个 `:` 即分隔符，account 正确 | 可直接重建 |
| issuer 含 `:` | label `A%3AB:u` → 先在 `%3A` 处切分 → issuer=`A`、account=`B:u`，且 query 不一致 → `IssuerMismatch`（2009） | 需重建策略 |
| issuer 为空 + username 含 `:` | label 仅 `a%3Ab` → issuer=`a`、account=`b` → **静默串位** | 需重建策略 |

**重建策略（两端必须逐字一致）**：

1. `uriIssuer = (issuer 含 ":" || issuer === "") ? "__mfa__" : issuer`（`"__mfa__"` 为不含冒号的固定占位符）。
2. `account` 直接用 `username` 原值（构造 URI 时百分号编码）。
3. `POST /api/v1/totp/create` 成功后，比对响应 `issuer`/`username` 与目标值；不一致时调用 `POST /api/v1/totp/edit/issuer` 或 `/edit/username` 校正（两接口只校验长度、接受 `:` 与空串；`application-database/src/tool/totp.rs:185-201` 直接写库，空串读回仍为 `""`）。
4. 校正请求失败**不回滚**已创建条目：保留占位值并计入失败明细，提示用户手动编辑。
5. 该策略同时解决「`issuer` 为 `None` 时响应显示为 `未知发行方`」与目标空串不一致的问题（统一由第 3 步校正）。
- 单条 `invalid` **不阻塞**整包：其余合法条目照常进入导入计划。
- `secret` 大小写不敏感，导入方应规范化为大写、无填充后入库。

## 7. 编解码约定

| 项 | 约定 | 说明 |
|---|---|---|
| JSON 序列化 | **紧凑**（无缩进、无多余空格），字段顺序固定为文档书写顺序 | 便于 diff/审计；两端不要求字节级一致，但**明文 body 必须能各自解析** |
| 数字 | 十进制整数，无前导零、无小数点 | `iterations`/`count`/`period`/`digits` |
| 字符串 | UTF-8，**无 BOM** | 文件与剪贴板文本皆同 |
| base64 | RFC 4648 标准字母表 + **规范 padding** | 微信 `wx.arrayBufferToBase64` 即标准；禁用 `-`/`_`。**解码器必须拒绝**：含空白/换行、非标准字母表、padding 缺失或多余、长度非 4 的倍数（两端对同一坏串必须给出同一错误码 `E_STRUCTURE`） |
| `meta.createdAt` | 严格正则 `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?(Z\|[+-]\d{2}:\d{2})$`；导出端写 `±HH:mm`（毫秒固定 3 位，偏移 0 写 `+00:00`），导入端另接受 `Z` 与 0~3 位毫秒 | 偏移 `HH ≤ 14`，`14:00` 分钟必须为 00；拒绝非法日历（如 `2026-02-30`）。手写解析，不用 `Date.parse`（老 JSCore 对带偏移 ISO 行为不一）；显示按设备本地时区 |
| `meta.app` | 可打印 ASCII（0x20~0x7E），**不含 `"` 与 `\\`**，≤ 32 字符 | 保证 canonical JSON 不产生转义（§4.2） |
| 文件后缀 | `.mfa`（推荐命名 `mfa-backup-YYYYMMDD-HHmm.mfa`） | **导入端不得依赖后缀**，一律按内容嗅探（`JSON.parse` 后看 `format`） |
| 文件编码 | 单文件、UTF-8、可含结尾换行（导入端须忽略首尾空白） | — |

## 8. 错误码与判定顺序

判定**严格按此顺序**，一旦命中即停止：

| # | 步骤 | 错误码 | 用户可见含义 |
|---|---|---|---|
| 1 | 文本不是 JSON / `format != "mfa"` | `E_FORMAT` | 不是本应用备份文件 |
| 2 | 整数且 `version > 1` | `E_VERSION` | 不支持的备份版本（非整数或 `< 1` 落到步骤 4 的 `E_STRUCTURE`） |
| 3 | `method` 不在注册表 | `E_METHOD` | 不支持的加密方式 |
| 4 | 结构/长度/范围非法（§3.1） | `E_STRUCTURE` | 备份文件结构异常 |
| 5 | kcv 不一致 | `E_PASSWORD` | 口令错误 |
| 6 | GCM 校验失败（含 `meta` 任一字段被改） | `E_CORRUPT` | 备份文件已损坏或被篡改 |
| 7 | payload 非法（含 `count` 不等） | `E_PAYLOAD` | 备份内容异常 |

> `meta.count` / `createdAt` / `source` / `app` 参与 AAD（§4.2）：任一字段被改即落在步骤 6 `E_CORRUPT`。步骤 7 的 `count` 校验是双保险：仅当 AAD 认证通过但 `count` 与解密条目数不符（如实现错误或人为重建信封）才触发 `E_PAYLOAD`。

> 步骤 1–4 在读口令之前即可完成：实现方应**先校验结构再要求输入口令**（避免用户白输一遍）。

## 9. 尺寸与限制

| 项 | 上限 | 违反时 |
|---|---|---|
| 单包条目数 | 500 | 导出端拒绝；导入端 `E_PAYLOAD` |
| 密文长度 | 1 MiB | 导出端拒绝；导入端 `E_STRUCTURE` |
| 迭代数 | 10000 ~ 500000 | `E_STRUCTURE` |
| `meta.app` | 32 字符（可打印 ASCII） | `E_STRUCTURE` |
| 单条 `tags` | 华为 1 / 微信按服务端上限（当前 1） | 超出丢弃多余项 |
| 剪贴板通道（实现方建议） | ≤ 50 条且编码后文本 ≤ 64 KiB | 超限时只走文件通道（非规范强制） |

## 10. 兼容与演进

### 10.1 预发布修订（唯一例外）

2026-11-08：v1 尚未对外发布（不存在任何外部历史文件），因此允许在**不升 `version`** 的前提下重定义 v1：

- `meta` 纳入 AAD（`AAD_PREFIX + canonicalMetaJson(meta)`）；
- `meta.createdAt` 从 UTC `Z` 改为带时区偏移；`meta.app` 收紧为可打印 ASCII。

**首次正式发布后本文件即为冻结基线**：此后任何影响解密结果的变更（含 AAD 拼接方式、时间格式、base64 变体、口令规范化）都必须升 `version` 并同步修改 AAD 与 KCV 标签。

### 10.2 常规规则

1. **新增可选字段**：允许，不升版本；老实现忽略未知字段。
2. **修改既有字段语义 / 删除字段**：必须升 `version`，且同步修改 AAD 与 KCV 标签。
3. **更换算法**：新增 `method` + 升 `version`；导入端先看 `version` 再看 `method`。
4. **不向前兼容的方向**：把"口令"换成"公钥加密"等本质变更，属新格式（新的 `format` 或 `version`）。
5. 同版本内**禁止**任何影响解密结果的隐式变更（含 AAD 拼接方式、base64 变体、口令规范化规则）——预发布修订见 §10.1。

## 11. 测试向量

- 文件：`docs/specs/mfa-backup-v1.vectors.json`（15 个用例，含 1 个完整 `exampleEnvelope`）
- 每个用例新增 `meta` 与 `aad` 字段：`aad` 为该用例实际使用的 AAD 原文（UTF-8），用于跨端逐字节对比；`meta.count` 与 `payloadJson` 的 `items.length` 一致（非 JSON 明文用例记 `0`）
- `exampleEnvelope` **必须逐字段等于 `case-12`**（`salt/iv/tag/kcv/data` 与该用例的 `saltB64/ivB64/tagB64/kcvB64/ciphertextB64` 相同，`meta` 与该用例的 `meta` 相同，口令 `12345678`），且与本文档 §3 内嵌示例完全一致；生成器 `gen-mfa-backup-vectors.mjs` 与文档同时改才算完成（改一侧即视为契约破裂）
- 生成器：`docs/specs/gen-mfa-backup-vectors.mjs`（`bun docs/specs/gen-mfa-backup-vectors.mjs`，确定性、幂等，自带解密回环自校验）
- oracle：`node:crypto`（OpenSSL 实现）——**独立于华为 native 实现与微信手写实现**，双端都对齐它即等价于双端互通。

### 11.1 用例覆盖

| id | 覆盖点 |
|---|---|
| case-01 | 空包（`items: []`）+ 迭代下限 10000 + 时区偏移 `+00:00` |
| case-02 | 3 条样本：中文 issuer / tag / pinned / 自定义 period+digits+algorithm + 负偏移 `-05:00` |
| case-03 | 中文口令 + 首尾空格（`trim`）+ 1 位毫秒的合法变体 |
| case-04 | emoji 与 NFD 组合字符（`NFC`） |
| case-05 ~ 08 | 明文 1 / 15 / 16 / 17 字节（GCM 块边界） |
| case-09 ~ 10 | 明文 1000 / 5000 字节 |
| case-11 | 默认迭代 100000 |
| case-12 | 单条账号（本文档 §3 示例） |
| case-13 | 100 条规模 |
| case-14 | JSON 转义字符（引号/反斜杠/换行） |
| case-15 | U+2028/U+2029 / emoji / 非 ASCII + 非整时偏移 `+05:45` |

### 11.2 断言清单（两端实现都必须跑）

1. `PBKDF2(passwordNormalized, salt, iterations, 32)` == `keyB64`
2. `AES-256-GCM(key, iv, aad).encrypt(plaintext)` 的密文 == `ciphertextB64`，tag == `tagB64`（`aad` 取该用例的 `aad` 字段）
3. `HMAC-SHA256(key, KCV)[0..8]` == `kcvB64`
4. `AES-256-GCM(...).decrypt(ciphertext, tag)` 回环 == `payloadJson`
5. 明文来源：若用例含 `plaintextB64` 则用它解码；否则 `payloadJson` 本身就是 UTF-8 明文（纯 ASCII 用例省略 `plaintextB64` 以免向量文件膨胀）
6. `aad` 字段 == 实现按 `canonicalMetaJson(meta)` 拼出的 AAD（验证 §4.2 拼接口径，而非只验证 Crypto 原语）
7. 便携验证：任一端都应能在**不依赖对方实现**的情况下独立跑通过上述 6 条

## 12. 安全要求（实现方强制）

| # | 要求 |
|---|---|
| S1 | 文件中**不得**出现口令、派生密钥或任何可用于直接解密的材料 |
| S2 | 口令/密钥/明文/密文**不得**写入任何日志、崩溃上报或本地持久化（仅内存） |
| S3 | 导入的文件一律视为**不可信输入**：先做结构与长度校验，再解析 |
| S4 | 导出前必须二次确认（明示"忘记口令无法恢复"）；应用锁开启时先做系统身份认证。**映射规则**：仅 `SUCCESS` 放行；`NO_CREDENTIAL`（设备确无凭据，系统已降级关闭应用锁）放行；**`SKIPPED` 必须拒绝**（它表示"在上一次验证结束 3 秒内 / 已有验证在飞"，若放行，拿到已解锁手机的人可先点取消、再在 3 秒内点导出从而跳过认证）；`CANCELED`/`FAILED` 拒绝并提示稍后重试 |
| S5 | 不实现任何"跳过口令/恢复口令"的旁路 |
| S6 | 剪贴板通道视为外泄风险通道：导出文案需提示"导入完成后清理剪贴板" |
| S7 | kcv 只用于本地判定口令，**不得**上报到任何服务端 |
| S8 | `meta` 虽参与 AAD，但仍是**明文**：不得在其中写入口令、密钥或其他敏感数据；`source`/`app` 仅用于展示，不承担安全语义 |

## 13. 附录：参考实现映射（仅供实现方对照）

| 环节 | 华为元服务（ArkTS） | 微信小程序（TS） |
|---|---|---|
| PBKDF2 | `createKdf('PBKDF2\|SHA256')` + `PBKDF2Spec{password,salt,iterations,keySize:32}` | 复用 `src/otp/internal/{sha256,hmac}` 循环 |
| AES key | `createSymKeyGenerator('AES256').convertKey({data})` | 派生字节直接使用 |
| GCM | `createCipher('AES256\|GCM\|NoPadding')` + `GcmParamsSpec{iv,aad,authTag}`（`doFinal` 结果末 16B 为 tag，需拆分） | 手写 AES-256 + GHASH/CTR（禁 BigInt，Uint32 分肢） |
| HMAC | `createMac('SHA256')` | `hmac.ts` |
| 随机 | `cryptoFramework.createRandom().generateRandomSync(n)` | `wx.getRandomValues({length})` → ArrayBuffer |
| base64 | `util.Base64Helper` | `wx.arrayBufferToBase64` + 自写解码 |
| UTF-8 | `util.TextEncoder` / `PBKDF2Spec` 字符串形态 | 自写 `utf8ToBytes` |

## 14. 变更记录

| 日期 | 变更 | 作者 |
|---|---|---|
| 2026-11-07 | 初版 v1（PBKDF2-SHA256 + AES-256-GCM，`.mfa` 后缀，kcv 区分口令错误） | Claude Opus 4.5 + yansongda |
| 2026-11-08 | v1 预发布修订（不升 version）：`meta` 纳入 AAD（canonical JSON）、`createdAt` 带时区偏移、`app` 收紧为可打印 ASCII；配套重生成全部向量 | Claude Opus 4.5 + yansongda |
