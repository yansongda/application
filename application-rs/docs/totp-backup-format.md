# TOTP 加密备份格式（v1）

> 适用范围：`application-rs` 的 `POST /api/v1/totp/backup/export`、`POST /api/v1/totp/backup/import`。
> 本文件是跨端契约：微信小程序、华为元服务、CLI/脚本若要自行实现导入，必须严格遵循本文。

## 1. 总体思路

- 服务端用用户输入的**备份密码**派生密钥，用 AES-256-GCM 加密一份 TOTP 条目数组。
- 导出返回 JSON 信封；用户自行保存该文本（复制/文件）。
- 导入时把信封作为请求体的 `backup` 对象提交，服务端校验信封头 → 派生密钥 → 解密 → 校验条目 → 逐条批量插入。
- 密码不落库、不参与任何找回流程：**忘记密码即备份不可恢复**。

## 2. 信封结构

```json
{
  "format": "application",
  "kind": "totp",
  "version": 1,
  "meta": {
    "created_at": "2026-06-28T14:30:00+08:00",
    "count": 12
  },
  "kdf": {
    "alg": "pbkdf2-sha256",
    "iterations": 600000,
    "salt": "<base64(16B)>"
  },
  "cipher": {
    "alg": "aes-256-gcm",
    "nonce": "<base64(12B)>"
  },
  "data": "<base64(ciphertext || 16B GCM tag)>"
}
```

| 字段 | 说明 |
|---|---|
| `format` | 固定 `application` |
| `kind` | 固定 `totp` |
| `version` | 信封版本，v1 固定 `1` |
| `meta.created_at` | 带时区偏移的 RFC3339 时间（导出端用服务器本地时区，如 `+08:00`；导入端接受任意合法偏移或 `Z`） |
| `meta.count` | 明文条目数，解密后必须与数组长度一致 |
| `kdf.alg` | 固定 `pbkdf2-sha256` |
| `kdf.iterations` | PBKDF2 迭代次数，导出为 `600000`；导入接受 `[100000, 1000000]` |
| `kdf.salt` | base64（标准字母表，无换行）编码的 16 字节随机 salt，每次导出重新生成 |
| `cipher.alg` | 固定 `aes-256-gcm` |
| `cipher.nonce` | base64（标准字母表，无换行）编码的 12 字节随机 nonce，每次导出重新生成 |
| `data` | base64（标准字母表，无换行）编码的 `密文 || 16 字节 GCM tag`；文本长度上限 512 KiB |

## 3. AAD（附加认证数据）

AES-GCM 的 AAD 为以下字段用 `\x1f`（U+001F）按固定顺序拼接后的 UTF-8 字节：

```
format \x1f kind \x1f version \x1f meta.created_at \x1f meta.count \
       \x1f kdf.alg \x1f kdf.iterations \x1f kdf.salt \
       \x1f cipher.alg \x1f cipher.nonce
```

以第 2 节示例为例：

```
application\x1ftotp\x1f1\x1f2026-06-28T14:30:00+08:00\x1f12\x1fpbkdf2-sha256\x1f600000\x1f<base64(16B)>\x1faes-256-gcm\x1f<base64(12B)>
```

- `data` 不参与 AAD（它本身是被认证的密文）。
- 任何头字段被改动都会导致 GCM 校验失败，服务端统一返回“密码错误或数据已损坏”（错误码 `2023`）。
- 该拼接顺序、分隔符、字段集合是 v1 契约的一部分，变更必须提升 `version`。

## 4. 明文 payload

解密后的明文是 **TOTP 条目数组**（不是对象，没有 `v` 字段；payload 结构由信封 `version` 决定）：

```json
[
  {
    "issuer": "GitHub",
    "username": "alice",
    "secret": "JBSWY3DPEHPK3PXP",
    "period": 30,
    "digits": 6,
    "algorithm": "SHA1",
    "tags": ["工作"],
    "pinned": true,
    "sort": 12
  }
]
```

| 字段 | 必填 | 规则 |
|---|---|---|
| `issuer` | 否 | ≤128 字符；空串按无发行方处理 |
| `username` | 是 | 1–128 字符 |
| `secret` | 是 | base32 可解码，归一化后 ≤128 字符；导出为大写、无填充 |
| `period` | 否（默认 30） | 1–600 |
| `digits` | 否（默认 6） | 6–8 |
| `algorithm` | 否（默认 `SHA1`） | `SHA1` / `SHA256` / `SHA512`（大小写不敏感，入库统一大写） |
| `tags` | 否（默认 `[]`） | 最多 1 个；每个去空白后 1–32 字符 |
| `pinned` | 否（默认 `false`） | 布尔 |
| `sort` | 否（默认 0） | u32；用于恢复列表顺序（列表按 `sort desc, id asc` 排序） |

约束：

- 条目数 ≤ **50**（`meta.count` 与数组长度都必须满足）。
- 导入**不去重**：重复导入会产生重复条目，由用户在列表页自行删除。

## 5. 密码与密钥

- 导出：密码 8–128 个字符（按 Unicode 标量计），按 UTF-8 原始字节参与 PBKDF2，**不 trim、不做 Unicode 归一化**。
- 导入：密码 1–128 个字符（只校验上限，保证将来提高导出门槛后旧备份仍可导入）。
- 密钥：`PBKDF2-HMAC-SHA256(password, salt, iterations, 32 字节)`，即 AES-256 的密钥。
- 密钥与明文在内存中使用后会 `zeroize` 擦除。

## 6. 导入校验顺序

1. 请求体 `backup` 必须是 JSON 对象（否则 `2024`）。
2. 信封反序列化（字段缺失/类型错误 → `2024`）。
3. 头字段校验：`format`/`kind`/`version`、`kdf.alg`/`cipher.alg`、迭代次数区间、`meta.count ≤ 50`、`created_at` 可解析、salt/nonce base64 长度、`data` 文本长度（失败 → `2024` / `2027`）。
4. PBKDF2 派生 + AES-GCM 解密（失败 → `2023`）。
5. 明文必须是数组，长度等于 `meta.count` 且 ≤ 50（失败 → `2024` / `2027`）。
6. 逐条字段校验与归一化（失败 → `2024`）。
7. 逐条批量插入；任一条失败即返回 `9903`（当前无事务，已写入的条目不会回滚）。

## 7. 接口

### 导出

```
POST /api/v1/totp/backup/export
Authorization: Bearer <access_token>
Content-Type: application/json

{"password": "YOUR_PASSPHRASE_HERE"}
```

成功响应 `data` 即信封对象。当前用户无条目 → `2026`；条目 > 50 → `2027`。

### 导入

```
POST /api/v1/totp/backup/import
Authorization: Bearer <access_token>
Content-Type: application/json

{"password": "YOUR_PASSPHRASE_HERE", "backup": { ...信封对象... }}
```

成功响应：

```json
{"imported": 12}
```

## 8. 错误码

| 码 | 变体 | 含义 |
|---|---|---|
| 2023 | `ParamsTotpBackupPasswordInvalid` | 备份密码不正确或备份数据已损坏 |
| 2024 | `ParamsTotpBackupFormatInvalid` | 备份数据格式不正确或版本不受支持 |
| 2025 | `ParamsTotpBackupPasswordFormatInvalid` | 备份密码长度不符合要求 |
| 2026 | `ParamsTotpBackupEmpty` | 暂无可导出的 TOTP 条目 |
| 2027 | `ParamsTotpBackupLimitExceeded` | 备份条目数超出上限（最多 50 条） |
| 9908 | `InternalCryptoFailed` | 加解密处理失败 |

## 9. 兼容与版本规则

- `version` 是唯一的协议版本号：新增/删除/改名任何信封字段、payload 字段语义、KDF/加密算法、AAD 结构，都必须 `version + 1`，且导入端保留旧版本的解密分支。
- `kdf.iterations` 每次都写入信封：未来提高导出迭代次数不影响旧备份导入（只要仍在导入区间内）。
- 条目上限、字段长度上限属于服务端策略，可在不改变格式的前提下调整（但降低上限会让旧备份导入失败，应只放宽不收紧）。

## 10. 安全说明（当前设计的取舍）

- 服务端数据库中 TOTP secret 本身是明文，`/api/v1/totp/all` 也会把 secret 下发给客户端本地算码；因此本功能保护的是**导出文件本身**（落盘、转发、剪贴板），而不是服务端被攻破的场景。
- 当前**未对请求日志脱敏**：`request_logger` 会把导出/导入请求体（含明文备份密码）写入应用日志。使用时应建议用户：
  - 使用**专用备份口令**，不要复用微信/华为/其他平台密码；
  - 仅在可信环境导出，并妥善保存备份文本。
- 如需降低该风险，后续可在 `application-api/src/middleware.rs` 的 `request_logger` 中对 `/api/v1/totp/backup/*` 跳过 body 读取，不影响本格式。
