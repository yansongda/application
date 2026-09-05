# 2026-09-05 22:16:02 Task 0 契约 spike：向量对照 + 引入方式验证 + 快照落盘

执行者：worker-low（Task 0）。分支 `feat/totp-local-compute`（基线 aa2dcf8，开工前 `git status --porcelain` 仅 `?? docs/`）。工具链：node v24.20.0 ✅ / npm 11.19.0 ✅ / deno ❌ 未安装。

## 子项 1：JS 向量断言（本地，硬性）—— PASS

- deno 兼容形式脚本（留档，本轮未执行——deno 未安装）：`docs/evidence/totp-local-compute/task-0-vector-assert.ts`，顶部 `import { TOTP } from "npm:otpauth@9.5.2"`，两个向量断言（RFC 6238 SHA1/8位 `94287082`；RFC 4226 Appendix D 6位 `287082`），stdout 输出 PASS/FAIL。
- **node 等价断言（本轮实际执行）**：`docs/evidence/totp-local-compute/task-0-vector-assert.node.mjs`，`npm pack otpauth@9.5.2` 解包后 import `./otpauth-9.5.2-pkg/dist/otpauth.esm.min.js`，断言逻辑与 deno 形式完全一致。

执行命令与输出：

```
$ cd docs/evidence/totp-local-compute && node task-0-vector-assert.node.mjs
PASS
PASS
```

- 1a（RFC 6238 SHA1/8位，secret=`GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ`，period=30，timestamp=59000ms）：**PASS**
- 1b（RFC 4226 Appendix D 6位，同 secret/SHA1/period=30/timestamp=59000ms 即 counter=1）：**PASS**

结论：`otpauth@9.5.2`（esm.min.js 构建）算码与 RFC 6238 / RFC 4226 向量一致；API 用法确认为 `new TOTP({issuer,label,algorithm,digits,period,secret})` + `generate({timestamp})`（ms），secret 接受 base32 字符串。

**deno 形式验收未跑（deno 未安装）**；deno 安装后需补跑：`cd <repo根> && deno run -A --no-lock docs/evidence/totp-local-compute/task-0-vector-assert.ts`（`--no-lock` 必须：repo 根无 deno.lock，否则会在 repo 根生成 deno.lock，触发 F1 白名单核查 FAIL）。

## 子项 2：测试环境对照（POST /api/v1/totp/all 逐条比对）—— 未实测（无 token）

本轮测试环境 token 未提供，**未实测**。按 plan 该项为 `0*` 软依赖，跳过；待用户提供 token 后补测：倒计时剩余 >5s 时发起 `POST https://application.test.yanda.net.cn/api/v1/totp/all`，对每条 `code` 用 otpauth 以相同 `config.period` 算码比对，并记录 secret base32 长度分布。

## 子项 3：Date 头检查 —— 近似探测（未带有效 token），正式结论留给 F3

按偏差指示 2 做近似探测（无 Authorization 头，预期非成功响应）：

```
$ curl -si -X POST https://application.test.yanda.net.cn/api/v1/totp/all -H 'Content-Type: application/json' -d '{}' | head -20
HTTP/2 200
access-control-allow-origin: *
alt-svc: h3=":443"; ma=3600
content-type: application/json; charset=utf-8
vary: origin
vary: access-control-request-method
vary: access-control-request-headers
x-request-id: 01M1RYSHCBXFNT0J6S92NVB3HJ
x-zeabur-ip-country: CN
x-zeabur-request-id: 36657b81-0b86-4edd-a463-c39ed826c9a9
server: TencentEdgeOne
age: 0
content-length: 116
date: Sat, 05 Sep 2026 14:15:34 GMT
strict-transport-security: max-age=16070400;includeSubDomains;preload
eo-log-uuid: 12967145560544963526
eo-cache-status: MISS
cache-control: max-age=0
nel: {"success_fraction":0.1,"report_to":"eo-nel","max_age":604800}
report-to: {"endpoints":[{"url":"https://nel.teo-rum.com/eo-cgi/nel","group":"eo-nel","max_age":604800}]}
```

响应体：`{"code":1000,"message":"认证失败: 缺少认证信息,请重新登录","request_id":"01M1RYSV1Z7QW92MG6BXFG04BB"}`

结论：响应**含 `Date:` 头**（`date: Sat, 05 Sep 2026 14:15:34 GMT`，HTTP/2 下响应头统一小写）。注意：未带 token 时业务失败码也返回 HTTP 200（`code:1000` 认证失败），而非 401/403——小程序侧错误判定需看业务 `code` 字段而非 HTTP 状态码。本结果为**近似探测（未带有效 token）**，带 token 场景的正式 `Date:` 头结论留给 F3。

## 子项 4：otpauth 包实物核验（npm pack otpauth@9.5.2）—— 三点全部符合

`npm pack otpauth@9.5.2` → `otpauth-9.5.2.tgz`（shasum `0d8a4e3e41a215b05c75114d752d9142a0b36c2e`），解包至 `docs/evidence/totp-local-compute/otpauth-9.5.2-pkg/`。执行命令与输出：

```
$ cd docs/evidence/totp-local-compute/otpauth-9.5.2-pkg
$ node -e "const p=require('./package.json'); console.log('main =', p.main)"
main = ./dist/otpauth.node.cjs
$ (grep -c "node:crypto" dist/otpauth.esm.min.js || true)
0
$ grep -n "export" dist/otpauth.d.ts
456:export { HOTP, Secret, TOTP, URI, version };
$ grep -n "static parse" dist/otpauth.d.ts
439:    static parse(uri: string, { hmac }?: {
```

核验三点结论：
1. `package.json` main 指向 `./dist/otpauth.node.cjs` ✅（node 入口顶层 require `node:crypto`；小程序 vendor 应用 esm 构建，不用 main 入口）
2. `dist/otpauth.esm.min.js` 中 `node:crypto` 计数 = **0** ✅（自包含，无 node 内置模块依赖，可作小程序 vendor）
3. `dist/otpauth.d.ts` 导出含 `URI` ✅：`export { HOTP, Secret, TOTP, URI, version };`；且 `URI.parse(uri)` 静态方法存在（d.ts:439），无 `TOTP.fromURI`，与设计文档附录 A 一致。

**核验后 tarball 与解包目录均已删除**（本文件落盘前执行，避免第三方完整包产物入库；快照仅记录结论）。

## 子项 5：快照落盘

本文件即快照：`docs/evidence/totp-local-compute/task-0-contract-snapshot.md`。目录内留档文件：`task-0-vector-assert.ts`（deno 兼容形式）、`task-0-vector-assert.node.mjs`（node 等价执行脚本，重跑需先重新 `npm pack` + 解包至 `otpauth-9.5.2-pkg/`）。

## 验收结果与偏差记录

- 验收标准逐条：1a/1b node 等价断言 PASS ✅；快照含 1-5 小节、2/3 显式标注"未实测（无 token）" ✅；三点核验结论在案、tarball 与解包目录已删 ✅；`.gitignore` 追加 4 行根级锚定条目后 `git status --porcelain` 不再出现 `?? docs/` ✅（见下）。
- **偏差 1（环境，主会话已裁定）**：deno 未安装，deno 形式验收未跑，以 node 等价断言替代并 PASS；deno 安装后需补跑（命令见子项 1）。
- **偏差 2（环境，主会话已裁定）**：测试环境 token 未提供，子项 2 未实测、子项 3 仅近似探测。
- **补充授权（主会话裁定，超出原 todo 范围）**：repo 根 `.gitignore` 末尾追加 4 行根级锚定条目（`/docs/implementation/`、`/docs/evidence/`、`/docs/learning/`、`/docs/totp-local-compute.md`；必须带前导斜杠，因 `application-rs/docs/util-http-refactor.md` 是已跟踪文件，裸 `docs/` 会误伤子目录）。追加后 `git status --porcelain` 不再出现 `?? docs/`。
- commit：本轮一次性 commit，仅含根 `.gitignore` + `docs/evidence/totp-local-compute/` 新建文件，message `docs(totp): TOTP 本地算码契约 spike 快照与向量验证`。

# 2026-09-05 22:25:00 主会话（main agent）亲自验证 Task 0 —— PASS

1. **向量断言亲自复现**（不信任 worker 输出）：`/tmp` 重新 `npm pack otpauth@9.5.2` + 解包 + `node task-0-vector-assert.node.mjs` → stdout 两行 `PASS`，exit=0；脚本内容级审查通过（与 deno 留档脚本断言逻辑一致，期望值与 RFC 6238 App-B / RFC 4226 App-D 原文相符）。复现后 tarball/解包目录已清理。
2. **otpauth 三点核验亲自复现**：main=`./dist/otpauth.node.cjs` ✅；`grep -c node:crypto dist/otpauth.esm.min.js`=0 ✅；`dist/otpauth.d.ts:456` `export { HOTP, Secret, TOTP, URI, version }` + `static parse` 命中 ✅（/tmp 验证后清理）。
3. **.gitignore 生效亲自确认**：`git status --porcelain` 空输出（`?? docs/` 消失）；追加为根级锚定 4 行，`application-rs/docs/util-http-refactor.md`（已跟踪）不受影响。
4. **commit 隔离亲自确认**：`git show --stat f8db6ae` 仅 `.gitignore` + Task 0 evidence 三件套（4 files, +178）。
5. **快照审查**：1-5 小节齐全、子项 2/3 显式标注"未实测（无 token）"、原始输出在案。
6. **deno 形式验收欠账**（环境性，已在 learning 记录）：deno 安装后补跑 `cd <repo根> && deno run -A --no-lock docs/evidence/totp-local-compute/task-0-vector-assert.ts`。

**结论：Task 0 验证通过（硬性项全过；token 相关软依赖项按 plan 标注未实测）。**

# 2026-09-05 22:36:00 主会话裁定 + 本轮执行：验收方式 deno→bun 升级，正式验收补跑 PASS

用户指令（本机有 bun 1.4.1，deno 确认未安装）：全仓 deno → bun，Task 0 验收欠账以 bun 形式补跑（Task 1.5）。脚本改动仅两处，断言逻辑零改动：

1. **新建 `package.json`**（同目录）：`{"name": "totp-local-compute-evidence", "private": true, "type": "module", "dependencies": {"otpauth": "9.5.2"}}`（pinned 无 ^）。
2. **`task-0-vector-assert.ts`**：`import { TOTP } from "npm:otpauth@9.5.2"` → `import { TOTP } from "otpauth"`（bun 不支持 npm: 前缀）；文件头验收命令改为 `cd docs/evidence/totp-local-compute && bun install && bun run task-0-vector-assert.ts`，删除"deno 安装后补跑"旧表述。断言体（RFC 6238 App-B 8 位 `94287082`、RFC 4226 App-D 6 位 `287082`、base32 secret、`generate({timestamp})` ms 语义）原样未动。

正式验收输出（bun 1.4.1）：

```
$ cd docs/evidence/totp-local-compute && bun install && bun run task-0-vector-assert.ts
bun install v1.4.1 (4661e494f)
Resolving dependencies
Resolved, downloaded and extracted [8]
Saved lockfile

+ otpauth@9.5.2

2 packages installed [1198.00ms]
PASS
PASS
exit=0
```

两行 `PASS` 与 Task 0 spike（node + npm pack 等价路径）及 RFC 原文期望值一致 → **Task 0 向量断言的 bun 形式正式验收通过，deno 验收欠账结清**。本轮 bun install 在本目录生成 bun.lock / node_modules（目录已被 `/docs/evidence/` gitignore，不入库）。
