/**
 * OTP 库不变量守卫（对照 ohos-otp 的 scripts/ci/check-invariants.mjs）。
 *
 * 只做静态机械检查，不依赖 SDK / 不执行被测代码；任一违规以 exit 1 失败：
 *  1. 全库禁止 BigInt（老设备兼容，SHA-512 必须 hi/lo 半字）
 *  2. 全库禁止 console.* 与 wx.*（库内零日志、零平台调用；平台能力只能落在 crypto-source.ts）
 *  3. internal/* 不得被 barrel 再导出
 *  4. Secret 不得实现 toString()（防密钥明文进入日志 / UI）
 *  5. 错误码必须恰好 18 个（v1 冻结）
 *  6. 业务代码不得引用 vendor / otpauth
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const otpDir = path.join(root, "src", "otp");
const violations = [];

function walk(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walk(full));
    } else if (entry.name.endsWith(".ts")) {
      files.push(full);
    }
  }
  return files;
}

/** 去掉注释后再做静态检查，避免文档里提到的禁用词（BigInt / wx / toString）误报。 */
function stripComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
}

function report(file, rule, detail) {
  violations.push(`${path.relative(root, file)}: [${rule}] ${detail}`);
}

for (const file of walk(otpDir)) {
  const text = stripComments(fs.readFileSync(file, "utf8"));
  if (/BigInt/.test(text)) {
    report(file, "no-bigint", "禁止 BigInt；SHA-512 使用 hi/lo 半字");
  }
  if (/console\./.test(text)) {
    report(file, "no-console", "库内禁止任何日志输出");
  }
  if (/wx\./.test(text)) {
    report(file, "no-wx", "库内禁止直接调用 wx API（随机源须由使用方注入）");
  }
}

const barrel = path.join(otpDir, "index.ts");
const barrelText = fs.readFileSync(barrel, "utf8");
if (/export\s*(type\s*)?\{?[^;]*from\s+"\.\/internal\/|export\s*\*\s*from\s+"\.\/internal\//.test(barrelText)) {
  report(barrel, "no-internal-export", "internal/* 不得进入 barrel");
}

const secret = path.join(otpDir, "secret.ts");
const secretText = stripComments(fs.readFileSync(secret, "utf8"));
if (/toString\s*\(/.test(secretText)) {
  report(secret, "no-toString", "Secret 刻意不实现 toString()");
}

const errors = path.join(otpDir, "errors.ts");
const errorsText = fs.readFileSync(errors, "utf8");
const codeCount = (stripComments(errorsText).match(/^\s{2}[A-Z0-9_]+\s*:\s*"[A-Z0-9_]+",$/gm) || []).length;
if (codeCount !== 18) {
  report(errors, "error-code-count", `错误码必须恰好 18 个，实际 ${codeCount}`);
}

// 业务代码 / 依赖声明不得再引用第三方 otpauth 或 vendor 产物
const businessFiles = [
  path.join(root, "src", "utils", "totp.ts"),
  path.join(root, "package.json"),
];
for (const file of businessFiles) {
  const text = fs.readFileSync(file, "utf8");
  if (/vendor\/otpauth|otpauth\.esm|"otpauth"\s*:|\.\.\/vendor/.test(text)) {
    report(file, "no-third-party-otp", "已改为自研 src/otp，不得重新引入 otpauth / vendor");
  }
}

if (violations.length > 0) {
  console.error("OTP invariants failed:");
  for (const v of violations) {
    console.error(`  - ${v}`);
  }
  process.exit(1);
}

console.log(`OTP invariants OK (${walk(otpDir).length} files, 18 error codes).`);
