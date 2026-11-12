# TOTP 微信小程序：端内算码改用自研 OTP 库（替换 vendored otpauth）

> **时间**：2026-11-07
> **状态**：已实施（待真机 / 开发者工具冒烟）
> **范围**：`wechat/miniprogram/totp/`（业务侧仅 `src/utils/totp.ts` 一个引用点）
> **参考实现**：`~/000-Coding/ohos-otp`（华为元服务在用的 `@yansongda/otp`）
>
> **现状更新（2026-11-12）**：OTP 实现已在 `github.com/yansongda/otp` monorepo 提取为独立 npm 包
> `@yansongda/miniprogram-otp@^1.0.1`（源码 `packages/core` 与本仓库原 `src/otp/` 同源，242 项算法测试由上游承接）。
> 本仓库已删除 `src/otp/` 与 `tests/otp/`，业务改从包入口导入；下文「为什么落在本仓库而非独立发版仓库」的结论
> 已被该包取代（包声明 `miniprogram: dist`，微信「构建 npm」可直接消费）。

## 1. 背景与决策

**改造前**：端内算码依赖 `otpauth@9.5.2` 官方 ESM dist 的**原样拷贝**（`src/vendor/otpauth.esm.min.js`，
27.6KB，内联 noble-hashes）。包 main 入口依赖 `node:crypto`，微信 packNpm 无法加载，只能 vendored；
升级需人工比对 SHA-256、同步 `package.json` 精确版本，且无法复用作者已有的 RFC 向量与测试矩阵。

**决策**：按 `ohos-otp` 的分层与契约，在仓库内实现零运行时依赖的纯 TypeScript OTP 库
`wechat/miniprogram/totp/src/otp/`，删除 vendor 与 `otpauth` 依赖。

**为什么落在本仓库而非独立发版仓库**：

- 微信小程序只能编译 `miniprogramRoot` 内的源码，独立 npm 包必须再走「构建 npm」且存在
  `main` 入口 / `exports` 子路径兼容风险（本轮已实测：noble 2.4.0 的 `main` 是抛错 stub，
  工具链只打包入口，子路径不可用）；
- 本仓库 CI 已具备 `biome` / `tsc`，新增 `bun test` 成本低；
- 结构上与 `ohos-otp` 的 `library/` 同构，后续若要抽独立仓库/发布 npm，可机械迁移。

## 2. 分层与文件

```
src/otp/
├── index.ts              # barrel：注册默认 HMAC 实现 + 导出公开符号
├── errors.ts             # 18 个冻结错误码 + OtpError（setPrototypeOf 修复）
├── options.ts            # OtpAlgorithm / OtpType（const 对象 + union）、DTO
├── secret.ts             # 规范化 / 字节视图 / 随机生成（注册表）/ toJSON 脱敏
├── hotp.ts / totp.ts     # 公开类（sync 全链路）
├── otpauth-uri.ts        # URI 解析 / 生成（手写 query 拆分）
└── internal/
    ├── base32.ts         # RFC 4648 §6 宽松 / 严格
    ├── counter.ts        # 8 字节大端（high/low 拆分）
    ├── truncate.ts       # RFC 4226 §5.3
    ├── digits.ts         # 唯一取模点 + 补零
    ├── time-step.ts      # step / remaining / progress / 恒定时间比较
    ├── engine.ts         # counter → code；verify 扫满窗口
    ├── hmac.ts           # RFC 2104（哈希函数与块大小注入）
    ├── sha1.ts / sha256.ts / sha512.ts   # 纯 32 位实现，SHA-512 用 hi/lo，无 BigInt
    ├── crypto-provider.ts # HmacProvider / RandomSource 接口 + 注册表
    └── crypto-source.ts   # 纯 JS HMAC 实现（唯一接触「平台能力」的文件）
```

**与 ArkTS 的差异（TS 特化，不影响契约）**：

- `enum` → `const` 对象 + union type：`"SHA1"` 字面量与 `OtpAlgorithm.SHA1` 均可赋值；
- 去掉 `*Sync` 后缀（TS 全链路同步），方法名与 ohos 保持一致；
- ArkTS 的 kit / kit-free 分层在 TS 中简化为「算法核心 ↔ crypto-source」两层，
  仍保留 `internal/*` 不进 barrel、测试可注入 provider 的约束。

## 3. 关键契约

| 项 | 结论 |
|---|---|
| HMAC | 纯 JS 实现；默认 provider 由 `index.ts` 导入时幂等注册 |
| 随机源 | **默认不注册**：微信只有异步 `wx.getRandomValues`；`Secret.generate()` 抛 `CRYPTO_NOT_INITIALIZED`，需要时注入同步 `RandomSource` |
| verify | 恒定时间；window 内扫完所有候选；返回 delta（`-0` 归一化为 `+0`） |
| 时钟偏移 | 所有时间入口（含显式 timestamp）统一叠加 `clockOffsetMs`；`syncClockOffset` 闭环不变量保留 |
| 错误 | 18 个错误码取值冻结；消息固定；不泄漏 secret / token |
| 兼容 | base32 宽松解析与 otpauth 一致；digits / algorithm 的兜底仍由 `utils/totp.ts` 负责 |

## 4. 变更清单

| 文件 | 变更 |
|---|---|
| `src/utils/totp.ts` | 唯一业务改动：`TOTP` 改为从 `../otp` 引入；`generate({ timestamp })` → `generate(timestamp)`；`normalizeDigits` / `normalizeAlgorithm` / 缓存 / `computeCode` 签名全部保留 |
| `src/otp/**` | 新增（约 1.8k 行实现 + README） |
| `src/vendor/**` | 删除（3 个文件） |
| `package.json` / `bun.lock` | 删除 `otpauth@9.5.2`；新增 `test` 脚本 |
| `biome.json` | 移除 `!src/vendor`；纳入 `tests/**/*`；对 `otpauth-uri.ts` 关闭 `noStaticOnlyClass`（与 ohos 的静态类 API 对齐） |
| `tsconfig.json` | `exclude` 增加 `tests`（Bun 运行时转译，不引入 bun 类型与小程序全局类型冲突） |
| `tests/otp/**` | 新增 12 个测试文件、242 项用例 |
| `.github/workflows/coding-linter.yml` | `lint-frontend-totp` 增加 `bun run test` |
| `AGENTS.md` / `CHANGELOG.md` / `docs/totp-local-compute.md` | 现状与维护约定更新 |

## 5. 验证证据（2026-11-07，本机）

| 项 | 结果 |
|---|---|
| `bun run test` | **242 pass / 0 fail**（12 文件） |
| RFC 4226 Appendix D | 10/10 |
| RFC 6238 Appendix B | 18/18（SHA1/256/512 × 6 时间点） |
| A.4 边界 counter（2^32、2^32+1、2^53-1） | 9/9（三算法，6/8 位） |
| digits=7 向量 | 3/3 |
| base32 RFC 4648 §10 | 7/7 + 严格模式尾长/填充位反例 |
| FIPS 180-4 哈希 / RFC 2202/4231 HMAC | 含空串、`abc`、56B、1M `a`、131B 长 key，全部经 Node/OpenSSL 独立复核 |
| 差分测试（vendor otpauth 9.5.2 vs 新库） | **3,240 组参数（6 secret × 3 算法 × 3 digits × 3 period × 20 时间戳）0 mismatch** |
| `bun run biome:check` | 65 files，0 error |
| `bun run typecheck` | 通过 |
| 真机 / 微信开发者工具 | **未执行**，列为合并前人工门槛 |

**人工冒烟清单**：

1. 列表页验证码与同窗口后端 `/totp/detail` 返回逐位一致；
2. 周期末验证码翻转、倒计时落在 `[1, period]`；
3. 断网后仍可算码；
4. 同时存在 SHA1 / SHA256 / SHA512 与 6 / 7 / 8 位条目时均正确。

## 6. 风险与回滚

| 风险 | 对策 |
|---|---|
| 纯 JS 哈希实现错误 | FIPS + RFC 向量 + OpenSSL 差分（哈希与 HMAC 双覆盖） |
| 微信编译器降级导致 `instanceof Error` 失效 | `OtpError` 构造器显式 `setPrototypeOf`；业务代码只读 `.code` |
| 老设备无 BigInt | 实现完全不用 BigInt（SHA-512 hi/lo 拆分）；与现状 otpauth（含 BigInt）相比反而更保守 |
| 测试未覆盖微信运行时 | 纯 JS 部分由 Bun 覆盖；真机冒烟为合并门槛 |
| 体积 | 删除 27.6KB 三方产物，替换为同量级自有源码；不改变上传结构 |

**回滚**：单 PR、无数据/协议迁移（secret / period / 缓存结构不变，码值逐位一致）。
`git revert` 即恢复 vendor 与依赖，无需清缓存、无后端配合。

## 7. 不做（Non-goals）

- 不发布 npm 包、不建独立仓库（结构已按可迁移方式组织）；
- 不提供异步随机 API（微信侧限制）；
- 不引入 BigInt、不改用 WebCrypto；
- 不改主小程序 `yansongda`（仍走后端算码）。
