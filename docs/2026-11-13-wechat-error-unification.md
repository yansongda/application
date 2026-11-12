# 微信 TOTP 小程序：统一自建错误类与用户文案入口

- 时间：2026-11-13
- 作者：pi agent
- 状态：已批准，实施中
- 范围：仅 `wechat/miniprogram/totp`。`yansongda` 主小程序与 upstream `otp` 库明确不在本次范围。

## 1. 背景与问题

`src/models/` 下两套错误类的**结构契约**不一致：

| 位置 | 现状 | 问题 |
|------|------|------|
| `src/models/error.ts` | `EE` 是普通 class，不 extends `Error`；无 `name`；无原型修复 | 无 `stack`；`pages/backup` 记录的 `(e as Error)?.name` 恒为 `undefined`；消费方被迫写 `instanceof Error \|\| instanceof EE` |
| `src/models/backup.ts` | `BackupParseError` extends `Error` + `name` + `setPrototypeOf` + 字符串码 | 与第三方 `OtpError` 同构，但基类能力重复实现 |

消费侧有 4 份文案实现（`utils/error.ts`、`pages/backup/index.ts` 本地副本、`api/backup.ts` 后端码表、`utils/totp-uri.ts` 的 `OtpError` 码表），fallback 文案不一致（“未知异常” / “操作失败，请重试”）。此外：

- `pages/totp/create/index.ts` 用 `err instanceof HttpError ? err.message : describeOtpError(err)`，新增错误类型时必须改分支；
- 普通 `Error` 的内部信息（`wx.login` 的 `errMsg`、`chooseMessageFile` 的 `errMsg`、`saveTokenBundle: ...` 英文）会直达用户 toast。

## 2. 整体方案

1. **统一基类**：`AppError<C extends string | number>` —— `extends Error`、`readonly code`、`Object.setPrototypeOf(this, new.target.prototype)`；子类只负责 `name` 字面量与码域。
2. **码域不合并**：`EE` / `HttpError` 保留数字业务码（`constant/error.ts` 的 `CODE`/`MESSAGE`）；`BackupParseError` 保留字符串预检码（对齐 `@yansongda/miniprogram-otp` 的 `OtpError`）。`AGENTS.md` 中“禁止 BackupParseError 改用 EE/数值码”的约束继续有效。
3. **单一用户文案入口**：`utils/error.ts#getErrorMessage` 只信任 `AppError.message`；域内码表留在所属模块（后端码表 `api/backup.ts`，`OtpError` 码表 `utils/totp-uri.ts`）。
4. **`describeOtpError` 改穷尽映射表**：`Record<OtpErrorCode, string | undefined>`，库新增码时编译期失败，运行期未知码回落通用文案。

不涉及：`yansongda`、upstream `otp`、数据结构 / storage / 后端接口契约。

## 3. 详细设计

### 3.1 `AppError` 契约

```ts
export abstract class AppError<C extends string | number> extends Error {
  readonly code: C;

  constructor(code: C, message: string) {
    super(message);
    Object.setPrototypeOf(this, new.target.prototype);
    this.code = code;
  }
}
```

- 已验证（本地 tsc `target: esnext` 实测）：三层继承（`AppError` → `EE` → `HttpError`）的 `instanceof` 全部成立；基类构造器赋值 `code`、子类不重声明时不会被 class field 重置。
- 已验证（tsc）：子类若重声明 `code`，编译器直接报 `TS2612` / `TS2564`，从类型层阻止 `useDefineForClassFields` 重置坑。
- 推断（未实测）：微信工具链若强制 ES5 降级，`new.target` 由 TS 编译兜底；以真机验证为准（`bun test` 运行原生 class，覆盖不到降级）。

### 3.2 类层次

| 类 | 基类 | code 域 | name |
|----|------|---------|------|
| `AppError` | `Error` | 泛型 | —（抽象） |
| `EE` | `AppError<number>` | 数字（默认 `CODE.UNKNOWN`，message 回落 `MESSAGE` 表） | `"EE"` |
| `WeixinError` | `EE` | 默认 `CODE.WEIXIN` | `"WeixinError"` |
| `HttpError` | `EE` | 默认 `CODE.HTTP` | `"HttpError"` |
| `BackupParseError` | `AppError<BackupParseErrorCode>` | 字符串（`as const`，值 = 键名） | `"BackupParseError"` |

### 3.3 `OtpErrorCode` 文案映射

`utils/totp-uri.ts` 使用 `Record<OtpErrorCode, string | undefined>`：

- 已映射：Base32/密钥组、配置组、URI 组、`UNSUPPORTED_OTPAUTH_TYPE`；
- 置 `undefined`（回落 `getErrorMessage`，保持现状）：`INVALID_WINDOW` / `INVALID_COUNTER` / `INVALID_TIMESTAMP` / `INVALID_TOKEN` / `CRYPTO_FAILED` / `CRYPTO_NOT_INITIALIZED` / `NOT_IMPLEMENTED`（应用当前不可达或无需细分）。

文案逐字保持现有测试断言，避免用户可见变化。

### 3.4 行为变化（唯一一处）

| 输入 | 改前 | 改后 |
|------|------|------|
| `HttpError` / `BackupParseError` / 已映射的 `OtpError` | `message` 或固定文案 | 不变 |
| 普通 `Error`（`wx.login` / `chooseMessageFile` 的 `errMsg`、内部英文） | 直接展示内部信息 | 统一“操作失败，请重试” |
| 非 `Error` 值 | “未知异常” / “操作失败，请重试” | 统一“操作失败，请重试” |

## 4. 推进策略

1. 落盘文档（本文件 + `docs/implementation/2026-11-13-wechat-error-unification.md`）。
2. 改 `models`（基类 + 两个错误类）→ 改 `utils`（describer + 映射表）→ 改 `pages`（删重复/m分支）→ 测试 → `AGENTS.md`。
3. 单测与静态检查全绿后，真机验证 log / 文案；本轮不合并、不推送。

回滚：单 commit revert，无数据/接口变更。

## 5. 风险与对策

| 风险 | 对策 |
|------|------|
| 普通 `Error.message` 不再展示，可能隐藏有用信息 | 已逐项核对：totp 内部 `Error` 均为 `wx.*` 的 `errMsg` 或英文内部信息，属改善 |
| `EE` 变真 `Error` 后 RealtimeLog 序列化形态变化 | 真机查看 `name`/`code` 是否可读 |
| 微信工具链 ES5 降级 | `new.target` 由 TS 编译兜底；真机验证 |
| 与 `yansongda` 共享文件开始漂移 | 本轮按用户要求不改 yansongda；在 `AGENTS.md` 记录“暂允许漂移”，待后续同步 |

## 6. 验证

- `bun run biome:check`、`bun run typecheck`、`bun run test`（基线：`115 pass / 10 files`）。
- 真机 / 开发者工具：断网加载、非法备份文本导入、取消文件选择三个场景。
- 详见证 `docs/implementation/2026-11-13-wechat-error-unification.md`。
