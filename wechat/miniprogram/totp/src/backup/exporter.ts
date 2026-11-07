/**
 * 导出编排：本地缓存条目 → 校验/归一 → 加密信封文本。
 * 缺 secret 或无法归一（非法 Base32 / period）的条目跳过并计数，不阻塞整体导出。
 */
import type { CacheItem } from "../types/totp";
import { encryptEnvelope, type RandomBytes } from "./crypto";
import { type BackupItem, sanitizeItem } from "./payload";
import { BackupError, BackupErrorCode, MAX_ITEMS } from "./spec";

export interface ExportOptions {
  password: string;
  app: string;
  rng: RandomBytes;
  iterations?: number;
  now?: () => Date;
}

export interface ExportResult {
  text: string;
  count: number;
  skipped: number;
}

const toRawItem = (item: CacheItem): Record<string, unknown> => {
  return {
    issuer: item.issuer,
    username: item.username,
    secret: item.secret,
    period: item.period,
    digits: item.digits,
    algorithm: item.algorithm,
    tags: item.tags,
    pinned: item.pinned,
  };
};

export const buildExport = async (
  items: CacheItem[],
  options: ExportOptions,
): Promise<ExportResult> => {
  const editable: BackupItem[] = [];
  let skipped = 0;

  for (const item of items) {
    if (typeof item.secret !== "string" || item.secret.length === 0) {
      skipped += 1;
      continue;
    }

    const sanitized = sanitizeItem(toRawItem(item));

    if (!sanitized.ok) {
      skipped += 1;
      continue;
    }

    editable.push(sanitized.item);
  }

  if (editable.length > MAX_ITEMS) {
    throw new BackupError({
      code: BackupErrorCode.E_PAYLOAD,
      detail: `单包条目数超过上限 ${MAX_ITEMS}`,
    });
  }

  const encrypted = await encryptEnvelope(editable, options.password, {
    source: "wechat",
    app: options.app,
    rng: options.rng,
    iterations: options.iterations,
    now: options.now,
  });

  return { text: encrypted.text, count: editable.length, skipped };
};
