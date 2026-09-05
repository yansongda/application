// Task 0 契约 spike：otpauth@9.5.2 RFC 向量断言（deno 兼容形式，留档）
//
// 正式验收命令（deno 安装后需补跑）：
//   cd <repo根> && deno run -A --no-lock docs/evidence/totp-local-compute/task-0-vector-assert.ts
//   （--no-lock 必须：repo 根无 deno.lock，不带该 flag 会在 repo 根生成 deno.lock，触发 F1 白名单核查 FAIL）
//
// 本轮实际执行（deno 未安装）：node 等价脚本 task-0-vector-assert.node.mjs，
// import `npm pack otpauth@9.5.2` 解包目录的 dist/otpauth.esm.min.js，断言逻辑与本文件完全一致。
// 详见同目录 task-0-contract-snapshot.md。
//
// 断言来源：
//   a) RFC 6238 Appendix B（SHA1/8位，T=59s → 94287082）
//      https://datatracker.ietf.org/doc/html/rfc6238#appendix-B
//   b) RFC 4226 Appendix D（SHA1/6位，counter=1 → 287082；timestamp=59000ms/period=30 → counter=1）
//      https://datatracker.ietf.org/doc/html/rfc4226#appendix-D
// stdout 输出两行 PASS/FAIL。
import { TOTP } from "npm:otpauth@9.5.2";

// base32("12345678901234567890") = GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ（RFC 6238/4226 共用测试密钥）
const secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
const timestamp = 59000; // ms，对应 T=59s，period=30 → counter=1

// a) RFC 6238 SHA1/8位
const totp8 = new TOTP({
  issuer: "RFC6238",
  label: "Task0",
  algorithm: "SHA1",
  digits: 8,
  period: 30,
  secret, // base32 字符串，otpauth 内部解析
});
const got8 = totp8.generate({ timestamp }); // generate({timestamp}) 单位为 ms
console.log(got8 === "94287082" ? "PASS" : `FAIL: got ${got8}, expected 94287082`);

// b) RFC 4226 Appendix D 6位（counter=1，即同一 TOTP 窗口）
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
