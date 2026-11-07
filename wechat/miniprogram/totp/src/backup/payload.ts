/**
 * 明文 payload：解析 / 校验 / 序列化（规范 §6）。
 *
 * secret 的严格 Base32 校验不在此处复刻：统一经 @utils/totp-uri 的 buildTotpUri
 * （内部 Secret.fromBase32 strict），符合「业务代码只经 totp-uri」的既有约束。
 */
import { OtpError } from "../otp/index";
import type { TotpAlgorithm } from "../types/totp";
import { buildTotpUri } from "../utils/totp-uri";
import { BackupErrorCode, MAX_ITEMS, MAX_TAGS_PER_ITEM } from "./spec";

export interface BackupItem {
  issuer: string;
  username: string;
  secret: string;
  period: number;
  digits: number;
  algorithm: TotpAlgorithm;
  tags: string[];
  pinned: boolean;
}

export interface InvalidItem {
  index: number;
  reason: string;
}

export type ParsePayloadResult =
  | {
      ok: true;
      items: BackupItem[];
      invalid: InvalidItem[];
    }
  | {
      ok: false;
      code: BackupErrorCode;
      detail: string;
    };

const ALGORITHMS: ReadonlyArray<TotpAlgorithm> = ["SHA1", "SHA256", "SHA512"];

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === "object" && value !== null && !Array.isArray(value);
};

const isTotpAlgorithm = (value: string): value is TotpAlgorithm => {
  return (ALGORITHMS as ReadonlyArray<string>).includes(value);
};

/** 规范化 secret：剔除空格与 `-`、去填充、转大写（规范 §6/§6.1）。 */
export const normalizeSecret = (secret: string): string => {
  return secret
    .replace(/\s/g, "")
    .replace(/-/g, "")
    .replace(/=/g, "")
    .toUpperCase();
};

const sanitizeTags = (value: unknown): string[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  const tags: string[] = [];

  for (const tag of value) {
    if (typeof tag !== "string" || tag.length < 1 || tag.length > 32) {
      continue;
    }

    tags.push(tag);

    if (tags.length >= MAX_TAGS_PER_ITEM) {
      break;
    }
  }

  return tags;
};

export type SanitizeResult =
  | { ok: true; item: BackupItem }
  | { ok: false; reason: string };

/** 单条归一：digit / algorithm 回落，tags 截断；非法 secret / period 判 invalid。 */
export const sanitizeItem = (raw: unknown): SanitizeResult => {
  if (!isRecord(raw)) {
    return { ok: false, reason: "条目不是对象" };
  }

  const issuer = raw.issuer;
  const username = raw.username;
  const secretRaw = raw.secret;

  if (typeof issuer !== "string" || issuer.length > 128) {
    return { ok: false, reason: "issuer 非法" };
  }

  if (typeof username !== "string" || username.length > 128) {
    return { ok: false, reason: "username 非法" };
  }

  if (typeof secretRaw !== "string" || secretRaw.length === 0) {
    return { ok: false, reason: "secret 缺失" };
  }

  const period = raw.period;

  if (
    typeof period !== "number" ||
    !Number.isInteger(period) ||
    period < 1 ||
    period > 86400
  ) {
    return { ok: false, reason: "period 非法" };
  }

  const digitsRaw = raw.digits;
  const digits =
    typeof digitsRaw === "number" &&
    Number.isInteger(digitsRaw) &&
    digitsRaw >= 6 &&
    digitsRaw <= 8
      ? digitsRaw
      : 6;

  const algorithmRaw = raw.algorithm;
  const algorithm =
    typeof algorithmRaw === "string" &&
    isTotpAlgorithm(algorithmRaw.toUpperCase())
      ? (algorithmRaw.toUpperCase() as TotpAlgorithm)
      : "SHA1";

  const secret = normalizeSecret(secretRaw);

  if (secret.length === 0) {
    return { ok: false, reason: "secret 缺失" };
  }

  try {
    buildTotpUri({
      issuer,
      account: username,
      secret,
      period,
      digits,
      algorithm,
    });
  } catch (e: unknown) {
    if (e instanceof OtpError) {
      return { ok: false, reason: "secret 不符合 Base32 规范" };
    }

    return { ok: false, reason: "条目无法重建为 otpauth URI" };
  }

  return {
    ok: true,
    item: {
      issuer,
      username,
      secret,
      period,
      digits,
      algorithm,
      tags: sanitizeTags(raw.tags),
      pinned: raw.pinned === true,
    },
  };
};

/**
 * 解析解密后的明文：整体结构错误 → E_PAYLOAD；
 * 单条非法只记入 invalid，不阻塞整包（规范 §6）。
 */
export const parsePayload = (text: string): ParsePayloadResult => {
  let raw: unknown;

  try {
    raw = JSON.parse(text);
  } catch {
    return {
      ok: false,
      code: BackupErrorCode.E_PAYLOAD,
      detail: "明文不是 JSON",
    };
  }

  if (!isRecord(raw) || raw.v !== 1) {
    return {
      ok: false,
      code: BackupErrorCode.E_PAYLOAD,
      detail: "payload.v 不为 1",
    };
  }

  const items = raw.items;

  if (!Array.isArray(items) || items.length > MAX_ITEMS) {
    return {
      ok: false,
      code: BackupErrorCode.E_PAYLOAD,
      detail: "items 不是数组或超过上限",
    };
  }

  const accepted: BackupItem[] = [];
  const invalid: InvalidItem[] = [];

  for (let i = 0; i < items.length; i++) {
    const result = sanitizeItem(items[i]);

    if (result.ok) {
      accepted.push(result.item);
    } else {
      invalid.push({ index: i, reason: result.reason });
    }
  }

  return { ok: true, items: accepted, invalid };
};

/** 紧凑 JSON，字段顺序固定（规范 §6/§7）。 */
export const stringifyPayload = (items: BackupItem[]): string => {
  return JSON.stringify({
    v: 1,
    items: items.map((item) => ({
      issuer: item.issuer,
      username: item.username,
      secret: item.secret,
      period: item.period,
      digits: item.digits,
      algorithm: item.algorithm,
      tags: item.tags,
      pinned: item.pinned,
    })),
  });
};
