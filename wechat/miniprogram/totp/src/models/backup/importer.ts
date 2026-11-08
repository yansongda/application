/**
 * 导入编排：结构校验 → 解密 → 计划（accepted / duplicates / invalid）→ 串行 create + 校正。
 *
 * 凭证重建策略（规范 §6.2，两端逐字一致）：
 *   uriIssuer = (issuer 含 ":" || issuer === "") ? "__mfa__" : issuer
 * 创建成功后按响应比对并 editIssuer/editUsername 校正（后端唯一写入入口是 otpauth URI，
 * totp-rs 在 label 首个冒号处切分，issuer 含冒号会串位甚至报 IssuerMismatch）。
 *
 * 本模块不直接调用 wx：api 由页面注入，纯逻辑可单测。
 */

import { type DecryptResult, decryptEnvelope } from "../../backup/crypto";
import { type Envelope, parseEnvelope } from "../../backup/envelope";
import type { BackupItem, InvalidItem } from "../../backup/payload";
import { BackupError, BackupErrorCode } from "../../backup/spec";
import type { CacheItem, Item } from "../../types/totp";
import { buildTotpUri } from "../../utils/totp-uri";

export const URI_ISSUER_PLACEHOLDER = "__mfa__";

export interface ImportApi {
  create(uri: string): Promise<Item>;
  editIssuer(data: { id: string; issuer: string }): Promise<unknown>;
  editUsername(data: { id: string; username: string }): Promise<unknown>;
  editTags(data: { id: string; tags: string[] }): Promise<unknown>;
  editPinned(data: { id: string; pinned: boolean }): Promise<unknown>;
}

export interface ImportPlanItem {
  item: BackupItem;
  uri: string;
}

export interface ImportPlan {
  accepted: ImportPlanItem[];
  duplicates: number;
  invalid: InvalidItem[];
  envelopeCount: number;
  envelope: Envelope;
  payload: DecryptResult;
}

/** 规范 §6.2：issuer 含冒号或为空时用固定占位符建号，再按响应校正。 */
export const planUriIssuer = (issuer: string): string => {
  return issuer.includes(":") || issuer.length === 0
    ? URI_ISSUER_PLACEHOLDER
    : issuer;
};

const dedupeKey = (item: BackupItem): string => {
  return `${item.secret}|${item.issuer}|${item.username}`;
};

const existingKeySet = (existing: CacheItem[]): Set<string> => {
  const keys = new Set<string>();

  for (const item of existing) {
    // 本地条目缺 secret 时不参与去重比较（规范 §6.1）
    if (typeof item.secret !== "string" || item.secret.length === 0) {
      continue;
    }

    keys.add(`${item.secret}|${item.issuer}|${item.username}`);
  }

  return keys;
};

export interface AnalyzeHooks {
  onProgress?: (done: number, total: number) => void;
  isCancelled?: () => boolean;
}

/** 结构错误/解密错误抛 BackupError；单条非法只计入 invalid。 */
export const analyze = async (
  text: string,
  password: string,
  existing: CacheItem[],
  hooks?: AnalyzeHooks,
): Promise<ImportPlan> => {
  const parsed = parseEnvelope(text);

  if (!parsed.ok) {
    throw new BackupError({ code: parsed.code, detail: parsed.detail });
  }

  const decrypted: DecryptResult = await decryptEnvelope(
    parsed.envelope,
    password,
    hooks,
  );

  const known = existingKeySet(existing);
  const accepted: ImportPlanItem[] = [];
  let duplicates = 0;

  for (const item of decrypted.items) {
    const key = dedupeKey(item);

    if (known.has(key)) {
      duplicates += 1;
      continue;
    }

    known.add(key);

    accepted.push({
      item,
      uri: buildTotpUri({
        issuer: planUriIssuer(item.issuer),
        account: item.username,
        secret: item.secret,
        period: item.period,
        digits: item.digits,
        algorithm: item.algorithm,
      }),
    });
  }

  return {
    accepted,
    duplicates,
    invalid: decrypted.invalid,
    envelopeCount: parsed.envelope.meta.count,
    envelope: parsed.envelope,
    payload: decrypted,
  };
};

export type ImportFailureStage =
  | "create"
  | "issuer"
  | "username"
  | "tags"
  | "pinned";

export interface ImportFailure {
  issuer: string;
  username: string;
  stage: ImportFailureStage;
  message: string;
}

export interface ImportReport {
  done: number;
  failed: ImportFailure[];
  canceled: boolean;
  notExecuted: number;
  withTags: number;
  withPinned: number;
}

export interface RunHooks {
  api: ImportApi;
  onProgress?: (done: number, total: number) => void;
  shouldCancel?: () => boolean;
  onCreated?: (item: Item) => void;
}

const describeError = (e: unknown): string => {
  if (e instanceof Error) {
    return e.message;
  }

  return String(e);
};

/**
 * 串行执行导入计划：create → 校正 issuer/username → tags/pinned。
 * 单条失败不中断；校正失败不回滚已创建条目（计入失败明细）。
 */
export const run = async (
  plan: ImportPlan,
  hooks: RunHooks,
): Promise<ImportReport> => {
  const total = plan.accepted.length;
  const report: ImportReport = {
    done: 0,
    failed: [],
    canceled: false,
    notExecuted: 0,
    withTags: 0,
    withPinned: 0,
  };

  for (let index = 0; index < total; index++) {
    if (hooks.shouldCancel?.() === true) {
      report.canceled = true;
      report.notExecuted = total - index;
      break;
    }

    const entry = plan.accepted[index];
    const item = entry.item;
    let stage: ImportFailureStage = "create";

    try {
      const created = await hooks.api.create(entry.uri);

      report.done += 1;
      hooks.onCreated?.(created);

      stage = "issuer";

      if (created.issuer !== item.issuer) {
        await hooks.api.editIssuer({ id: created.id, issuer: item.issuer });
      }

      stage = "username";

      if (created.username !== item.username) {
        await hooks.api.editUsername({
          id: created.id,
          username: item.username,
        });
      }

      if (item.tags.length > 0) {
        stage = "tags";
        await hooks.api.editTags({ id: created.id, tags: item.tags });
        report.withTags += 1;
      }

      if (item.pinned) {
        stage = "pinned";
        await hooks.api.editPinned({ id: created.id, pinned: true });
        report.withPinned += 1;
      }
    } catch (e: unknown) {
      report.failed.push({
        issuer: item.issuer,
        username: item.username,
        stage,
        message: describeError(e),
      });
    }

    hooks.onProgress?.(index + 1, total);
  }

  return report;
};

/** 结构校验后再要求口令的辅助：非法文本抛 BackupError（页面据此提示，不索要口令）。 */
export const precheck = (text: string): Envelope => {
  const parsed = parseEnvelope(text);

  if (!parsed.ok) {
    throw new BackupError({ code: parsed.code, detail: parsed.detail });
  }

  return parsed.envelope;
};

export { BackupErrorCode };
