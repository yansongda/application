# src/otp —— 微信小程序版 `@yansongda/otp`

零运行时依赖的 RFC 4226 / 6238 HOTP / TOTP 实现，分层与契约对齐华为元服务在用的 ArkTS 库
`@yansongda/otp`（源码仓库 `~/000-Coding/ohos-otp`）。

> 本目录只被业务代码 `src/utils/totp.ts` 引用；`internal/*` 不进 barrel，测试经深路径直接 import。

## 能力

- HOTP（RFC 4226）与 TOTP（RFC 6238），SHA1 / SHA256 / SHA512，6 / 7 / 8 位
- `otpauth://` URI 解析与生成（Google Authenticator Key URI Format）
- TOTP 的 `remaining()` / `progress()`（倒计时与环形进度）、漂移窗口 `verify(..., { window })`、
  时钟偏移校准 `syncClockOffset()`
- 统一错误模型（18 个冻结错误码）

## 使用

```ts
// 微信运行时不做目录 index 解析：必须写 "../otp/index"，不能写 "../otp"
import { TOTP } from "../otp/index";

const totp = new TOTP({ secret: "JBSWY3DPEHPK3PXP", digits: 6, period: 30 });
totp.generate(Date.now()); // "287082"（示例时间）
```

业务封装见 `src/utils/totp.ts`（带实例缓存、digits/algorithm 兜底，签名保持不变）。

## API

| 成员 | 语义 |
|---|---|
| `new TOTP({ secret, algorithm?, digits?, period?, t0?, clockOffsetMs?, minSecretBits?, issuer?, account? })` | 构造期即校验；默认 SHA1 / 6 / 30 / t0=0 |
| `totp.generate(timestampMs?)` | 返回验证码；缺省当前时刻 |
| `totp.verify(token, { timestamp?, window? })` | 恒定时间比对，返回命中窗口的 delta；未命中 `null` |
| `totp.remaining(timestampMs?)` / `totp.progress(timestampMs?)` | `[1, period]` / `[0, 1)` |
| `totp.syncClockOffset(delta)` / `totp.clockOffsetMs` | 校准时钟偏移（单位：时间步） |
| `totp.toURI()` / `TOTP.fromURI(uri)` | 规范 otpauth URI 往返 |
| `new HOTP({ secret, counter?, ... }).generate(counter?)` | HOTP，其余语义同上 |
| `Secret.fromBase32(s, { strict? })` / `.fromBytes` / `.generate` | 规范化、严格校验、随机生成（见下） |
| `OTPAuthURI.parse(uri, { strict? })` / `.build(params)` | URI 解析 / 生成 |

## 不变量（改动必须遵守）

1. 全库零 `console.*` / 日志；`OtpError` 消息为固定文案，绝不包含 secret / token。
2. `Secret` 刻意不实现 `toString()`；`toJSON()` 返回 `[REDACTED]`（`JSON.stringify` 会调用）。
3. `verify` 在窗口内**扫完所有候选**后才返回首个命中 delta，禁止早退优化。
4. 取模只在 `internal/digits.ts` 发生一次；`truncate` 只做 `& 0x7f`（31 位非负）。
5. 位运算全部 32 位安全；SHA-512 使用 hi/lo 半字，**禁止引入 BigInt**（老设备兼容）。
6. `internal/*` 不进 barrel；`index.ts` 在导入时幂等注册默认 HMAC 实现（不发起计算）。

## 错误码

`EMPTY_SECRET`、`INVALID_BASE32_CHAR`、`INVALID_BASE32_PADDING`、`SECRET_TOO_SHORT`、`SECRET_TOO_WEAK`、
`INVALID_ALGORITHM`、`INVALID_DIGITS`、`INVALID_PERIOD`、`INVALID_T0`、`INVALID_COUNTER`、
`INVALID_TIMESTAMP`、`INVALID_WINDOW`、`INVALID_TOKEN`、`CRYPTO_FAILED`、`CRYPTO_NOT_INITIALIZED`、
`INVALID_OTPAUTH_URI`、`UNSUPPORTED_OTPAUTH_TYPE`、`NOT_IMPLEMENTED`。

## 覆盖边界（重要）

- **随机源默认不注册**：微信只有异步 `wx.getRandomValues`，无法满足同步 API；
  `Secret.generate()` 默认抛 `CRYPTO_NOT_INITIALIZED`，需要时由使用方 `registerRandom()` 注入同步实现。
  本小程序只做端内算码，不使用随机生成。
- 测试运行在 Bun（纯 JS 环境），已覆盖 RFC 4226 / 6238 / 4648 官方向量与哈希 / HMAC 向量；
  **真机 / 微信开发者工具冒烟仍是合并前的人工门槛**。
- `otpauth://` 不是 RFC，遵循 Google Authenticator 事实标准（IANA Provisional #13829）；
  解析容忍大小写 / 空白 / 尾部 `=`，`{ strict: true }` 才校验规范 base32。

## 测试

```bash
bun run test                # tests/otp/，242 项
bun run check:otp-invariants # 不变量静态守卫（无 BigInt / 无日志 / internal 不进 barrel 等）
bun run typecheck           # 主 tsc（tests 不在其中）
bun run biome:check
```
