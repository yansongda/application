/**
 * OTP 依赖守卫（替代原 `check-otp-invariants.mjs` 的源码级不变量检查）。
 *
 * 背景：OTP 实现已迁移到 npm 包 `@yansongda/miniprogram-otp`（源码在上游 otp monorepo，
 * 242 项算法测试与不变量守卫由上游 CI 承接）。本脚本守住本项目仍需自证的三条线：
 *  1. 依赖声明必须是 caret 范围，且解析版本与这里的基线一致（升级必须显式改本文件）
 *  2. 微信实际消费的 `dist/index.js` 指纹必须与基线一致（防供应链篡改 / 静默漂移）
 *  3. 关键行为（RFC 4226/6238 向量、漂移窗口、URI 往返、错误码）在安装产物上仍然成立
 * 另外校验业务代码不再深 import 已删除的 `src/otp` 或包内 dist 路径。
 *
 * 任一失败以 exit 1 结束；脚本本身零额外依赖，CI 与本地共用。
 */
import { createHash } from "node:crypto";
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

const PACKAGE = "@yansongda/miniprogram-otp";
/** 依赖基线：升级包版本时必须同步改这里（caret 范围 + dist 指纹 + 便于人工确认）。 */
const EXPECTED_VERSION = "1.0.1";
/** `dist/index.js` 的 sha512（base64），随版本锁定；升级后由 `npm pack` 产物重新计算。 */
const EXPECTED_DIST_SHA512 =
  "4WjuiaSv7WNYs5/9ANeE2OTMvgphZtXr48nYJKJIzPM67kxEKXvMt7sMUfGaOguxfJDWaVj8u1buGJx1xXj6Eg==";

const failures = [];
const fail = (message) => failures.push(message);

// ---- 1) 依赖声明与安装版本 ----

const packageJson = JSON.parse(
  fs.readFileSync(path.join(root, "package.json"), "utf8"),
);
const range = packageJson.dependencies?.[PACKAGE];

if (typeof range !== "string") {
  fail(`package.json 缺少 dependencies["${PACKAGE}"]`);
} else if (range !== `^${EXPECTED_VERSION}`) {
  fail(
    `依赖范围应为 ^${EXPECTED_VERSION}（caret，显式升级），实际 "${range}"；` +
      "升级时需同步更新本脚本的版本基线、dist 指纹并做真机冒烟",
  );
}

const pkgDir = path.join(root, "node_modules", PACKAGE);
if (!fs.existsSync(pkgDir)) {
  fail(`node_modules 中未找到 ${PACKAGE}，请先执行 bun install`);
}

const installedVersion = fs.existsSync(pkgDir)
  ? JSON.parse(fs.readFileSync(path.join(pkgDir, "package.json"), "utf8"))
      .version
  : null;

if (installedVersion !== EXPECTED_VERSION) {
  fail(
    `已安装版本 ${installedVersion} 与基线 ${EXPECTED_VERSION} 不一致；` +
      "请运行 bun install 或按升级流程更新基线",
  );
}

// bun.lock 是解析结果的权威来源：条目格式为 ["@yansongda/miniprogram-otp@x.y.z", "", {}, "sha512-..."]
const lockText = fs.readFileSync(path.join(root, "bun.lock"), "utf8");
const lockMatch = lockText.match(
  new RegExp(`"${PACKAGE}":\\s*\\["${PACKAGE}@([^"]+)"`),
);

if (lockMatch === null) {
  fail("bun.lock 中缺少该依赖条目，请执行 bun install");
} else if (lockMatch[1] !== EXPECTED_VERSION) {
  fail(
    `bun.lock 解析版本 ${lockMatch[1]} 与基线 ${EXPECTED_VERSION} 不一致`,
  );
}

// ---- 2) 微信实际消费的 dist 指纹 ----

const distFile = path.join(pkgDir, "dist", "index.js");
if (!fs.existsSync(distFile)) {
  fail("未找到 dist/index.js；微信「构建 npm」依赖该产物，请检查安装是否完整");
} else {
  const digest = createHash("sha512")
    .update(fs.readFileSync(distFile))
    .digest("base64");

  if (digest !== EXPECTED_DIST_SHA512) {
    fail(
      "dist/index.js 指纹与基线不一致（疑似静默升级或产物被篡改）；" +
        "确认上游发布后更新 EXPECTED_DIST_SHA512 并做真机冒烟",
    );
  }
}

// ---- 3) 安装产物上的行为冒烟 ----

const require = createRequire(path.join(root, "package.json"));
let otp = null;
try {
  otp = require(PACKAGE);
} catch (error) {
  fail(`require("${PACKAGE}") 失败：${error?.message ?? error}`);
}

if (otp !== null) {
  // RFC 6238 附录 B 的官方 seed（与上游 vectors 同源，禁止改值）
  const SHA1_SEED = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
  const SHA256_SEED = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA";
  const SHA512_SEED =
    "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA";

  const smoke = [
    {
      name: "TOTP SHA1 t=59s",
      run: () => new otp.TOTP({ secret: SHA1_SEED }).generate(59_000),
      expected: "287082",
    },
    {
      name: "TOTP SHA256 t=59s / 8 位",
      run: () =>
        new otp.TOTP({
          secret: SHA256_SEED,
          algorithm: "SHA256",
          digits: 8,
        }).generate(59_000),
      expected: "46119246",
    },
    {
      name: "TOTP SHA512 t=59s / 8 位",
      run: () =>
        new otp.TOTP({
          secret: SHA512_SEED,
          algorithm: "SHA512",
          digits: 8,
        }).generate(59_000),
      expected: "90693936",
    },
    {
      name: "HOTP counter=0",
      run: () => new otp.HOTP({ secret: SHA1_SEED }).generate(0),
      expected: "755224",
    },
    {
      name: "verify 漂移窗口（delta = 命中窗口相对当前时间步的偏移）",
      run: () => {
        const totp = new otp.TOTP({ secret: SHA1_SEED });
        const token = totp.generate(59_000);
        return [
          totp.verify(token, { timestamp: 59_000 }),
          totp.verify(token, { timestamp: 89_000, window: 1 }),
          totp.verify(token, { timestamp: 119_000, window: 1 }),
        ];
      },
      expected: [0, -1, null],
    },
    {
      name: "remaining / progress",
      run: () => {
        const totp = new otp.TOTP({ secret: SHA1_SEED });
        return [
          totp.remaining(59_000),
          totp.progress(59_000) >= 0 && totp.progress(59_000) < 1,
        ];
      },
      expected: [1, true],
    },
    {
      name: "otpauth URI 往返",
      run: () => {
        const totp = new otp.TOTP({
          secret: SHA1_SEED,
          issuer: "ACME",
          account: "alice@acme.com",
        });
        return totp.toURI() === otp.TOTP.fromURI(totp.toURI()).toURI();
      },
      expected: true,
    },
    {
      name: "strict base32 规范化",
      run: () => otp.Secret.fromBase32("jbswy3dpehpk3pxp").toBase32(),
      expected: "JBSWY3DPEHPK3PXP",
    },
  ];

  for (const { name, run, expected } of smoke) {
    let actual;
    try {
      actual = JSON.stringify(run());
    } catch (error) {
      actual = `ERR:${error?.code ?? error?.name ?? "unknown"}`;
    }
    if (actual !== JSON.stringify(expected)) {
      fail(`行为冒烟失败 [${name}]：期望 ${JSON.stringify(expected)}，实际 ${actual}`);
    }
  }

  // 错误模型：code / name / instanceof 必须完好（业务按 code 分支做文案映射）
  const errorCases = [
    { name: "strict base32 拒绝截断密钥", run: () => otp.Secret.fromBase32("AAA", { strict: true }), code: "INVALID_BASE32_PADDING" },
    { name: "digits 非 6/7/8", run: () => new otp.TOTP({ secret: SHA1_SEED, digits: 5 }), code: "INVALID_DIGITS" },
    { name: "空密钥", run: () => new otp.TOTP({ secret: "" }), code: "EMPTY_SECRET" },
    { name: "微信端无同步随机源", run: () => otp.Secret.generate(20), code: "CRYPTO_NOT_INITIALIZED" },
  ];

  for (const { name, run, code } of errorCases) {
    let thrown = null;
    try {
      run();
    } catch (error) {
      thrown = error;
    }
    if (!(thrown instanceof otp.OtpError)) {
      fail(`错误模型失败 [${name}]：抛出物不是 OtpError（实际 ${thrown?.name ?? thrown}）`);
    } else if (thrown.name !== "OtpError" || thrown.code !== code) {
      fail(
        `错误模型失败 [${name}]：期望 OtpError/${code}，实际 ${thrown.name}/${thrown.code}`,
      );
    }
  }
}

// ---- 4) 业务代码不得深 import 已删除的源码目录或包内路径 ----

const SRC_DIR = path.join(root, "src");
const IGNORED_DIRS = new Set(["miniprogram_npm"]);
const FORBIDDEN = [
  { pattern: /from\s+"[^"]*(\.\.\/)?otp\/index"/, detail: "src/otp 已删除，OTP 只经包入口导入" },
  { pattern: /from\s+"[^"]*otp\/internal\//, detail: "包内 internal 不对业务开放" },
  { pattern: /from\s+"[^"]*miniprogram_npm\/@yansongda/, detail: "不得直接引用构建产物目录，使用包名导入" },
];

const walk = (dir) => {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (IGNORED_DIRS.has(entry.name)) {
      continue;
    }
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walk(full));
    } else if (entry.name.endsWith(".ts")) {
      files.push(full);
    }
  }
  return files;
};

for (const file of walk(SRC_DIR)) {
  const text = fs.readFileSync(file, "utf8");
  for (const { pattern, detail } of FORBIDDEN) {
    if (pattern.test(text)) {
      fail(`${path.relative(root, file)}：${detail}`);
    }
  }
}

// ---- 汇总 ----

if (failures.length > 0) {
  console.error("OTP dependency guard failed:");
  for (const item of failures) {
    console.error(`  - ${item}`);
  }
  process.exit(1);
}

console.log(
  `OTP dependency guard OK (${PACKAGE}@${EXPECTED_VERSION}, dist sha512 pinned, ${walk(SRC_DIR).length} src files checked).`,
);
