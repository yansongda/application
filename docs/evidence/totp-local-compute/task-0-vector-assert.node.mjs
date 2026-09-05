// Task 0 契约 spike：otpauth@9.5.2 RFC 向量断言（node 等价脚本，本轮实际执行方式）
//
// 前置：在本目录执行 `npm pack otpauth@9.5.2 && tar -xzf otpauth-9.5.2.tgz`（解包目录 otpauth-9.5.2-pkg/）。
// 运行：cd docs/evidence/totp-local-compute && node task-0-vector-assert.node.mjs
// 断言逻辑与 task-0-vector-assert.ts（deno 兼容留档）完全一致。
// 注意：解包目录在核验后删除，本脚本留档供复现（重跑需先重新 npm pack + 解包）。
import { TOTP } from "./otpauth-9.5.2-pkg/dist/otpauth.esm.min.js";

// base32("12345678901234567890") = GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ
const secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
const timestamp = 59000; // ms，T=59s，period=30 → counter=1

// a) RFC 6238 SHA1/8位：期望 94287082
const totp8 = new TOTP({
  issuer: "RFC6238",
  label: "Task0",
  algorithm: "SHA1",
  digits: 8,
  period: 30,
  secret,
});
const got8 = totp8.generate({ timestamp });
console.log(got8 === "94287082" ? "PASS" : `FAIL: got ${got8}, expected 94287082`);

// b) RFC 4226 Appendix D 6位：期望 287082
const totp6 = new TOTP({
  issuer: "RFC4226",
  label: "Task0",
  algorithm: "SHA1",
  digits: 6,
  period: 30,
  secret,
});
const got6 = totp6.generate({ timestamp });
console.log(got6 === "287082" ? "PASS" : `FAIL: got ${got6}, expected 287082`);
