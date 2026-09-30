# src/vendor

## 这是什么

- `otpauth.esm.min.js`：[otpauth](https://github.com/hectorm/otpauth) 官方 npm 包 `dist/otpauth.esm.min.js` 的**原样拷贝**（自包含 ESM，内联 noble-hashes，无 `node:crypto` 依赖）。
- `otpauth.esm.min.d.ts`：官方 `dist/otpauth.d.ts` 的**原样拷贝**（仅重命名以匹配 import 基名，供 tsc 解析类型）。

两者均已与 npm 官方产物做过 SHA-256 / 逐字节比对一致，**禁止在本目录做任何内容修改**。

## 为什么 vendor

包的 main 入口指向 `dist/otpauth.node.cjs`，顶层 `require('node:crypto')`，微信小程序运行时与 packNpm 均无法加载；ESM 构建自包含可直接 import。背景见仓库 `docs/totp-local-compute.md` 3.5 节。

**2026-09-06 已实测确认 npm 直构不可用，请勿尝试改回**：packNpm 引擎（与 devtools「构建 npm」同源）无法解析包 main（`.cjs` 后缀被错误处理为 `otpauth.node.cjs.js`，告警 `Npm package entry file not found`）；devtools 内以包名 import + 构建 npm 实测加载失败。

## 版本同步约束（重要）

- 当前版本：**9.5.2**。运行时实际加载的是本目录文件；`node_modules` 中的包与 `package.json` 依赖声明仅用于锁文件与版本记录。
- `package.json` 中 otpauth **必须固定精确版本（无 `^`）**，并与本目录文件版本保持一致。
- 两者漂移不会有任何构建期报错，只能靠本约定约束：升级时必须同时更新本目录两个文件与 `package.json`。

## 升级步骤

1. `npm pack otpauth@<新版本>` 并解包（tarball 内为 `package/dist/`）
2. 确认产物无 Node 依赖：`grep -c "node:crypto" package/dist/otpauth.esm.min.js` 应为 `0`
3. 拷贝 `package/dist/otpauth.esm.min.js` → 本目录同名文件
4. 拷贝 `package/dist/otpauth.d.ts` → 本目录 `otpauth.esm.min.d.ts`（注意重命名）
5. `package.json` 中 otpauth 固定版本号改为同一版本，执行 `bun install` 更新 `bun.lock`
6. 用 RFC 4226 Appendix D（10 组）与 RFC 6238 Appendix B（SHA1，5 组）官方向量对新文件跑断言
7. `bun run typecheck && bun run biome:check` 通过
