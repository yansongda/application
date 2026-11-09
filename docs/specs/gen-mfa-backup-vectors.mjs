// 生成 docs/specs/mfa-backup-v1.vectors.json（跨端共享测试向量）。
//
// 运行：bun docs/specs/gen-mfa-backup-vectors.mjs
// 产物：docs/specs/mfa-backup-v1.vectors.json（覆盖写入，确定性生成，无时间戳）
//
// 设计要点：
// - oracle 为 node:crypto（OpenSSL 实现），独立于华为 cryptoFramework 与微信手写实现，
//   因此双端"对齐 oracle"即等价于双端互相对齐。
// - salt/iv 由固定种子派生（sha256），保证每次重新生成得到完全一致的向量，便于 diff 与评审。
// - 每个 case 同时给出派生密钥（keyB64），便于定位是 KDF 错还是分组/GCM 错。

import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  pbkdf2Sync,
  randomBytes,
} from "node:crypto";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SPEC_VERSION = 1;
const METHOD = "PBKDF2-SHA256/AES-256-GCM";
const AAD_PREFIX = `mfa|${SPEC_VERSION}|${METHOD}|`;
const KCV_LABEL = "mfa-kcv|1";

// meta 的规范序列化（规范 §4.2）：字段顺序固定、紧凑 JSON。
// app 必须是可打印 ASCII（无引号/反斜杠），因此这里不会出现 JSON 转义。
const canonicalMetaJson = (meta) =>
  JSON.stringify({
    count: meta.count,
    createdAt: meta.createdAt,
    source: meta.source,
    app: meta.app,
  });

const aadOf = (meta) => Buffer.from(`${AAD_PREFIX}${canonicalMetaJson(meta)}`, "utf8");

const HERE = dirname(fileURLToPath(import.meta.url));

// ── 口令规范化：trim → NFC（UTF-8 编码由 Buffer.from 完成）──
const normalizePassword = (raw) => raw.trim().normalize("NFC");

const b64 = (buf) => Buffer.from(buf).toString("base64");

// 固定种子派生 salt/iv：保证确定性
const seedBytes = (label, len) =>
  Buffer.from(createHash("sha256").update(label).digest()).subarray(0, len);

const deriveKey = (passwordRaw, salt, iterations) =>
  pbkdf2Sync(Buffer.from(normalizePassword(passwordRaw), "utf8"), salt, iterations, 32, "sha256");

const computeKcv = (key) =>
  Buffer.from(createHmac("sha256", key).update(Buffer.from(KCV_LABEL, "utf8")).digest()).subarray(0, 8);

// AES-256-GCM 加密：返回密文与 16 字节 tag（node 默认 authTagLength=16）
const encryptGcm = (key, iv, aad, plaintextBuf) => {
  const cipher = createCipheriv("aes-256-gcm", key, iv, { authTagLength: 16 });

  cipher.setAAD(aad);

  const ct = Buffer.concat([cipher.update(plaintextBuf), cipher.final()]);
  const tag = cipher.getAuthTag();

  return { ct, tag };
};

// 明文 payload：字段顺序固定，紧凑 JSON（与规范 §3.3 一致）
const itemJson = (o) => ({
  issuer: o.issuer,
  username: o.username,
  secret: o.secret,
  period: o.period ?? 30,
  digits: o.digits ?? 6,
  algorithm: o.algorithm ?? "SHA1",
  tags: o.tags ?? [],
  pinned: o.pinned ?? false,
});

const payload = (items) => JSON.stringify({ v: 1, items: items.map(itemJson) });

const sampleItems = [
  {
    issuer: "GitHub",
    username: "alice@example.com",
    secret: "JBSWY3DPEHPK3PXP",
    tags: ["工作"],
    pinned: true,
  },
  {
    issuer: "银行",
    username: "bob",
    secret: "GEZDGNBVGY3TQOJQ",
    period: 60,
    digits: 8,
    algorithm: "SHA256",
    tags: [],
    pinned: false,
  },
  {
    issuer: "",
    username: "carol",
    secret: "MFRGGZDFMZTWQ2LK",
  },
];

// 明文长度梯度（0 / 1 / 15 / 16 / 17 / 1000 / 5000 字节）+ 中文/emoji 内容
const pad = (n) => "x".repeat(n);

// 默认导出时间戳（东八区；导出端固定 3 位毫秒、偏移 0 写 +00:00，规范 §4.1）
const DEFAULT_CREATED_AT = "2026-11-07T08:00:00.000+08:00";

// 明文非 JSON 的用例（GCM 块边界）无 items，count 记 0（只验证密码学路径）
const countOf = (payloadJson) => {
  try {
    const parsed = JSON.parse(payloadJson);
    return Array.isArray(parsed.items) ? parsed.items.length : 0;
  } catch {
    return 0;
  }
};

const metaOf = (c) => ({
  count: countOf(c.payloadJson),
  createdAt: c.createdAt ?? DEFAULT_CREATED_AT,
  source: c.source ?? "huawei",
  app: c.app ?? "1.9.0",
});

const cases = [
  {
    id: "case-01",
    note: "最小空包（items 为空数组），迭代数下限 10000",
    passwordRaw: "password",
    iterations: 10000,
    createdAt: "2026-11-07T00:00:00.000+00:00",
    payloadJson: payload([]),
  },
  {
    id: "case-02",
    note: "3 条样本（含中文 issuer、tag、pinned、自定义 period/digits/algorithm）",
    passwordRaw: "correct horse battery staple",
    iterations: 10000,
    createdAt: "2026-11-06T19:00:00.000-05:00",
    payloadJson: payload(sampleItems),
  },
  {
    id: "case-03",
    note: "中文口令 + 首尾空格（验证 trim → NFC 规范化）",
    passwordRaw: "   密码1234   ",
    iterations: 10000,
    createdAt: "2026-11-07T08:00:00.5+08:00",
    payloadJson: payload(sampleItems),
  },
  {
    id: "case-04",
    note: "emoji 口令 + NFC 组合字符（café 组合形式与分解形式应得到同一密钥）",
    passwordRaw: "🔐 cafe\u0301 mãter",
    iterations: 10000,
    payloadJson: payload(sampleItems),
  },
  {
    id: "case-05",
    note: "明文仅 1 字节（边界：GCM 最短明文）",
    passwordRaw: "pw-000001",
    iterations: 10000,
    payloadJson: pad(1),
  },
  {
    id: "case-06",
    note: "明文 15 字节（GCM 块边界前）",
    passwordRaw: "pw-000002",
    iterations: 10000,
    payloadJson: pad(15),
  },
  {
    id: "case-07",
    note: "明文 16 字节（GCM 等于一个块）",
    passwordRaw: "pw-000003",
    iterations: 10000,
    payloadJson: pad(16),
  },
  {
    id: "case-08",
    note: "明文 17 字节（GCM 跨块 + 余 1 字节）",
    passwordRaw: "pw-000004",
    iterations: 10000,
    payloadJson: pad(17),
  },
  {
    id: "case-09",
    note: "明文 1000 字节",
    passwordRaw: "pw-000005",
    iterations: 10000,
    payloadJson: pad(1000),
  },
  {
    id: "case-10",
    note: "明文 5000 字节（接近单包典型上限）",
    passwordRaw: "pw-000006",
    iterations: 10000,
    payloadJson: pad(5000),
  },
  {
    id: "case-11",
    note: "默认迭代数 100000（上线默认值）",
    passwordRaw: "a-longer-passphrase-2026",
    iterations: 100000,
    payloadJson: payload(sampleItems),
  },
  {
    id: "case-12",
    note: "迭代数 10000 + 纯数字弱口令（仅测试解密路径，不校验强度）",
    passwordRaw: "12345678",
    iterations: 10000,
    payloadJson: payload(sampleItems.slice(0, 1)),
  },
  {
    id: "case-13",
    note: "100 条规模（单包上限 500 条的真机压力自测不放向量）",
    passwordRaw: "pw-000007",
    iterations: 10000,
    payloadJson: payload(
      Array.from({ length: 100 }, (_, i) =>
        itemJson({
          issuer: `Svc-${i}`,
          username: `user-${i}`,
          secret: "JBSWY3DPEHPK3PXP",
          tags: i % 3 === 0 ? ["工作"] : [],
          pinned: i % 10 === 0,
        }),
      ),
    ),
  },
  {
    id: "case-14",
    note: "明文含 JSON 转义字符与换行（验证 JSON 序列化一致性）",
    passwordRaw: "pw-000008",
    iterations: 10000,
    payloadJson: payload([
      itemJson({ issuer: 'A"B\\C', username: "line1\nline2", secret: "JBSWY3DPEHPK3PXP" }),
    ]),
  },
  {
    id: "case-15",
    note: "明文含 U+2028/U+2029 与二进制外观字符（非 ASCII）",
    passwordRaw: "pw-000009",
    iterations: 10000,
    createdAt: "2026-11-07T12:15:00.000+05:45",
    payloadJson: payload([
      itemJson({ issuer: "S\u2028T\u2029", username: "😀🀄️", secret: "JBSWY3DPEHPK3PXP" }),
    ]),
  },
];

const build = (c) => {
  const meta = metaOf(c);
  const aad = aadOf(meta);
  const salt = seedBytes(`mfa-vectors|salt|${c.id}`, 16);
  const iv = seedBytes(`mfa-vectors|iv|${c.id}`, 12);
  const key = deriveKey(c.passwordRaw, salt, c.iterations);
  const plaintext = Buffer.from(c.payloadJson, "utf8");
  const { ct, tag } = encryptGcm(key, iv, aad, plaintext);
  const kcv = computeKcv(key);

  // 纯 ASCII 明文的 UTF-8 字节 == payloadJson 本身，省略 plaintextB64 以免向量文件翻倍
  const isAscii = /^[\x00-\x7F]*$/.test(c.payloadJson);

  return {
    id: c.id,
    note: c.note,
    passwordRaw: c.passwordRaw,
    passwordNormalized: normalizePassword(c.passwordRaw),
    iterations: c.iterations,
    meta,
    aad: aad.toString("utf8"),
    saltB64: b64(salt),
    ivB64: b64(iv),
    keyB64: b64(key),
    payloadJson: c.payloadJson,
    ...(isAscii ? {} : { plaintextB64: b64(plaintext) }),
    ciphertextB64: b64(ct),
    tagB64: b64(tag),
    kcvB64: b64(kcv),
  };
};

const built = cases.map(build);

// 端到端 envelope 示例（用 case-12：单条账号，规范 §3 内嵌示例与本文件必须逐字段一致）
const example = built.find((c) => c.id === "case-12");
const envelope = {
  format: "mfa",
  version: SPEC_VERSION,
  method: METHOD,
  key: {
    iterations: example.iterations,
    salt: example.saltB64,
    iv: example.ivB64,
    tag: example.tagB64,
    kcv: example.kcvB64,
  },
  data: example.ciphertextB64,
  meta: { ...example.meta },
};

const out = {
  spec: "mfa-backup",
  version: SPEC_VERSION,
  method: METHOD,
  aadPrefix: AAD_PREFIX,
  kcvLabel: KCV_LABEL,
  oracle: "node:crypto (OpenSSL) via bun; 生成脚本 docs/specs/gen-mfa-backup-vectors.mjs",
  note:
    "本文件为跨端唯一事实源：华为 ArkTS 与微信 TS 实现都必须逐字节对齐这些向量。" +
    "重新生成必须保持幂等（无时间戳，salt/iv 由固定种子派生）。",
  exampleEnvelope: envelope,
  cases: built,
};

const target = join(HERE, "mfa-backup-v1.vectors.json");
const serialized = `${JSON.stringify(out, null, 2)}\n`;

writeFileSync(target, serialized, "utf8");

// 可选：导出华为 ohosTest 用的 ArkTS 常量文件（禁止手工转录向量）。
// 大 payload 只保留 payloadSha256，避免把 13KB 明文塞进源码字面量。
const emitIndex = process.argv.indexOf("--emit-ets");

if (emitIndex !== -1) {
  const etsTarget = process.argv[emitIndex + 1];

  if (!etsTarget) {
    throw new Error("--emit-ets 需要目标路径");
  }

  const fixtureHash = createHash("sha256").update(serialized).digest("hex");
  const lines = [];

  lines.push("// AUTO-GENERATED by docs/specs/gen-mfa-backup-vectors.mjs —— 禁止手工修改。");
  lines.push(`// fixture sha256: ${fixtureHash}`);
  lines.push("export interface IBackupVectorMeta {");
  lines.push("  count: number;");
  lines.push("  createdAt: string;");
  lines.push("  source: string;");
  lines.push("  app: string;");
  lines.push("}");
  lines.push("");
  lines.push("export interface IBackupVectorCase {");
  lines.push("  id: string;");
  lines.push("  note: string;");
  lines.push("  passwordRaw: string;");
  lines.push("  passwordNormalized: string;");
  lines.push("  iterations: number;");
  lines.push("  meta: IBackupVectorMeta;");
  lines.push("  aad: string;");
  lines.push("  saltB64: string;");
  lines.push("  ivB64: string;");
  lines.push("  keyB64: string;");
  lines.push("  plaintextB64: string;");
  lines.push("  payloadJson: string;");
  lines.push("  payloadSha256: string;");
  lines.push("  ciphertextB64: string;");
  lines.push("  tagB64: string;");
  lines.push("  kcvB64: string;");
  lines.push("}");
  lines.push("");
  lines.push(`export const BACKUP_AAD_PREFIX: string = ${JSON.stringify(AAD_PREFIX)};`);
  lines.push(`export const BACKUP_KCV_LABEL: string = ${JSON.stringify(KCV_LABEL)};`);
  lines.push(`export const BACKUP_VECTORS: IBackupVectorCase[] = [`);

  for (const c of built) {
    const keepPayload = 'undefined' === typeof c.plaintextB64;

    lines.push("  {");
    lines.push(`    id: ${JSON.stringify(c.id)},`);
    lines.push(`    note: ${JSON.stringify(c.note)},`);
    lines.push(`    passwordRaw: ${JSON.stringify(c.passwordRaw)},`);
    lines.push(`    passwordNormalized: ${JSON.stringify(c.passwordNormalized)},`);
    lines.push(`    iterations: ${c.iterations},`);
    lines.push(`    meta: ${JSON.stringify(c.meta)},`);
    lines.push(`    aad: ${JSON.stringify(c.aad)},`);
    lines.push(`    saltB64: ${JSON.stringify(c.saltB64)},`);
    lines.push(`    ivB64: ${JSON.stringify(c.ivB64)},`);
    lines.push(`    keyB64: ${JSON.stringify(c.keyB64)},`);
    lines.push(`    plaintextB64: ${JSON.stringify(c.plaintextB64 ?? "")},`);
    lines.push(`    payloadJson: ${JSON.stringify(keepPayload ? c.payloadJson : "")},`);
    lines.push(`    payloadSha256: ${JSON.stringify(createHash("sha256").update(c.payloadJson, "utf8").digest("hex"))},`);
    lines.push(`    ciphertextB64: ${JSON.stringify(c.ciphertextB64)},`);
    lines.push(`    tagB64: ${JSON.stringify(c.tagB64)},`);
    lines.push(`    kcvB64: ${JSON.stringify(c.kcvB64)},`);
    lines.push("  },");
  }

  lines.push("];");
  lines.push("");

  writeFileSync(etsTarget, lines.join("\n"), "utf8");

  console.log(`已生成 ${etsTarget}：${built.length} 个用例常量，fixture ${fixtureHash.slice(0, 8)}`);
}

// 自校验：解密回环（防生成器自身配置错误）
for (const c of built) {
  const key = deriveKey(c.passwordRaw, Buffer.from(c.saltB64, "base64"), c.iterations);
  const decipher = createDecipheriv("aes-256-gcm", key, Buffer.from(c.ivB64, "base64"), {
    authTagLength: 16,
  });

  decipher.setAAD(Buffer.from(c.aad, "utf8"));
  decipher.setAuthTag(Buffer.from(c.tagB64, "base64"));
  const back = Buffer.concat([decipher.update(Buffer.from(c.ciphertextB64, "base64")), decipher.final()]);

  if (back.toString("utf8") !== c.payloadJson) {
    throw new Error(`自校验失败：${c.id}`);
  }
  if (b64(key) !== c.keyB64) {
    throw new Error(`密钥派生不稳定：${c.id}`);
  }
}

// 兜底：crypto 随机源可用（仅断言接口存在，不写入向量）
randomBytes(4);

console.log(`已生成 ${target}：${built.length} 个用例，自校验通过`);
