// Task 0 契约 spike：otpauth@9.5.2 RFC 向量断言（bun 形式）
//
// 正式验收命令：
//   cd docs/evidence/totp-local-compute && bun install && bun run task-0-vector-assert.ts
//
// 历史备注：原为 deno 兼容形式（import "npm:otpauth@9.5.2"），deno 未安装未执行；
// 2026-09-05 Task 1.5 包管理器 deno→bun 迁移后以上述 bun 命令正式验收。
// node 等价脚本 task-0-vector-assert.node.mjs 保留留档，断言逻辑与本文件一致。
// 详见同目录 task-0-contract-snapshot.md。
//
// 断言来源：
//   a) RFC 6238 Appendix B（SHA1/8位，T=59s → 94287082）
//      https://datatracker.ietf.org/doc/html/rfc6238#appendix-B
//   b) RFC 4226 Appendix D（SHA1/6位，counter=1 → 287082；timestamp=59000ms/period=30 → counter=1）
//      https://datatracker.ietf.org/doc/html/rfc4226#appendix-D
// stdout 输出两行 PASS/FAIL。
import { TOTP } from "otpauth";

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
