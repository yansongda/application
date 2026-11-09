# src/backup —— MFA 加密备份格式库

口令加密备份（`.mfa`）的**纯库**：格式定义、严格解析、密码学原语与编解码。
契约唯一事实源见仓库根 `docs/specs/mfa-backup-v1.md`，跨端共享向量见
`docs/specs/mfa-backup-v1.vectors.json`（oracle = `node:crypto`）。

> **本目录零业务依赖**：不得 import `../api` / `../pages` / `../utils` / `../models` / `../types`；
> 唯一允许的跨目录依赖是 `../otp`（复用 SHA-256 / HMAC 与 Base32 严格校验）。
> 边界由 `scripts/check-otp-invariants.mjs` 静态守卫，可独立成库（对齐 `src/otp`）。
>
> 导出 / 导入的**业务编排**在 `src/models/backup/`（依赖缓存类型、后端 API），不属于本库。

## 能力

| 模块 | 职责 |
|---|---|
| `spec.ts` | 规范常量（`AAD_PREFIX` / KCV 标签 / 尺寸 / 迭代范围 / `MAX_APP_LENGTH`）、8 个错误码、`BackupAlgorithm` |
| `time.ts` | `createdAt` 编解码（带时区偏移、手写解析与日历校验、本地时间显示辅助） |
| `base64.ts` | 标准字母表 + 规范 padding；**严格解码**拒绝空白 / base64url / padding 异常 |
| `pbkdf2.ts` | PBKDF2-HMAC-SHA256（同步内核仅供单测；运行期走分片异步，可进度/可取消） |
| `aes-gcm.ts` | AES-256-GCM（手写，`Uint32` 分肢 GHASH，**不使用 BigInt**） |
| `crypto.ts` | 口令规范化（trim → NFC）→ 派生 → kcv → 加解密编排 |
| `envelope.ts` | 信封结构 / 严格解析（判定顺序 = 规范 §8）/ 紧凑序列化 / `canonicalMetaJson` + `buildAad`（meta 参与 AAD） |
| `payload.ts` | 明文校验 / 归一 / 序列化（单条非法只记 `invalid`，不阻塞整包） |
| `index.ts` | barrel：唯一对外入口 |

## 使用

```ts
import { BackupError, BackupErrorCode, decryptEnvelope, parseEnvelope } from "../backup/index";

// 1) 先结构校验（不需要口令，规范 §8 步骤 1-4）
const parsed = parseEnvelope(text);
if (!parsed.ok) {
  // parsed.code: E_FORMAT / E_VERSION / E_METHOD / E_STRUCTURE
}

// 2) 再解密（kcv 先判口令，GCM 再判损坏；失败抛 BackupError）
try {
  const result = await decryptEnvelope(parsed.envelope, password);
  // result.items / result.invalid / result.envelope
} catch (e) {
  if (e instanceof BackupError && e.code === BackupErrorCode.E_PASSWORD) {
    // 口令错误（与 E_CORRUPT 区分）
  }
}
```

## 不变量（CI 强制）

- 禁止 `BigInt`（老设备 JSCore 不支持；AES-GCM 用 `Uint32` 分肢实现）
- 禁止 `console.*`（日志统一走业务层 `utils/logger`）
- 禁止 `Math.random`（salt / iv 必须来自 `wx.getRandomValues`）
- 禁止 `require(`（小程序运行时不做目录解析，一律 ESM 相对路径）
- 禁止 `node:crypto` / 平台 crypto（必须是纯 JS 实现，与华为原生实现字节对齐）

## 测试

- `tests/mfa/backup-*.test.ts`：15 组共享向量（含 1/15/16/17 字节 GCM 块边界、中文/emoji/NFC、100 条规模）
- 重新生成向量：`bun docs/specs/gen-mfa-backup-vectors.mjs`（确定性、幂等、自带解密回环自校验）
- 规范要求：文档、向量、生成器**同时改**才算完成，改一侧即视为契约破裂
