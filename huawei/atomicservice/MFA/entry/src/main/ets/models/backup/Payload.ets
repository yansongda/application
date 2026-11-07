// 明文 payload：解析 / 校验 / 序列化（规范 §6）。
// secret 的严格 Base32 校验走 @yansongda/otp 的 Secret.fromBase32(strict)（本工程唯一密钥校验入口）。
import { Secret } from '@yansongda/otp';
import { BackupErrorCode, BackupSpec } from './Spec';

const ALGORITHMS: string[] = ['SHA1', 'SHA256', 'SHA512'];

export interface IBackupItem {
  issuer: string;
  username: string;
  secret: string;
  period: number;
  digits: number;
  algorithm: string;
  tags: string[];
  pinned: boolean;
}

export interface IInvalidItem {
  index: number;
  reason: string;
}

export interface IRawItem {
  issuer?: string;
  username?: string;
  secret?: string;
  period?: number;
  digits?: number;
  algorithm?: string;
  tags?: string[];
  pinned?: boolean;
}

interface IRawPayload {
  v?: number;
  items?: IRawItem[];
}

export interface IPayloadPayload {
  v: number;
  items: IBackupItem[];
}

export class SanitizeResult {
  readonly ok: boolean;
  readonly item: IBackupItem | undefined;
  readonly reason: string;

  constructor(ok: boolean, item: IBackupItem | undefined, reason: string) {
    this.ok = ok;
    this.item = item;
    this.reason = reason;
  }
}

export class PayloadParseResult {
  readonly ok: boolean;
  readonly items: IBackupItem[];
  readonly invalid: IInvalidItem[];
  readonly code: BackupErrorCode;
  readonly detail: string;

  constructor(ok: boolean, items: IBackupItem[], invalid: IInvalidItem[],
    code: BackupErrorCode, detail: string) {
    this.ok = ok;
    this.items = items;
    this.invalid = invalid;
    this.code = code;
    this.detail = detail;
  }
}

function invalidResult(reason: string): SanitizeResult {
  return new SanitizeResult(false, undefined, reason);
}

// 规范化 secret：剔除空白与 '-'、去填充、转大写（规范 §6/§6.1）
export function normalizeSecret(secret: string): string {
  let out: string = '';

  for (let i = 0; i < secret.length; i++) {
    const ch: string = secret.charAt(i);

    if (' ' === ch || '\t' === ch || '\n' === ch || '\r' === ch || '-' === ch || '=' === ch) {
      continue;
    }

    out += ch;
  }

  return out.toUpperCase();
}

// 去重键 secret|issuer|username（规范 §6.1）
export function dedupeKey(secret: string, issuer: string, username: string): string {
  return `${secret}|${issuer}|${username}`;
}

function sanitizeTags(value: string[] | undefined): string[] {
  const tags: string[] = [];

  if ('undefined' === typeof value || !Array.isArray(value)) {
    return tags;
  }

  for (const tag of value) {
    if ('string' !== typeof tag || tag.length < 1 || tag.length > 32) {
      continue;
    }

    tags.push(tag);

    if (tags.length >= BackupSpec.MAX_TAGS_PER_ITEM) {
      break;
    }
  }

  return tags;
}

export function sanitizeItem(raw: IRawItem): SanitizeResult {
  const issuer: string | undefined = raw.issuer;
  const username: string | undefined = raw.username;

  if ('string' !== typeof issuer || issuer.length > 128) {
    return invalidResult('issuer 非法');
  }

  if ('string' !== typeof username || username.length > 128) {
    return invalidResult('username 非法');
  }

  if ('string' !== typeof raw.secret || raw.secret.length === 0) {
    return invalidResult('secret 缺失');
  }

  const period: number | undefined = raw.period;

  if ('number' !== typeof period || !Number.isInteger(period) || period < 1 || period > 86400) {
    return invalidResult('period 非法');
  }

  let digits: number = 6;
  const digitsRaw: number | undefined = raw.digits;

  if ('number' === typeof digitsRaw && Number.isInteger(digitsRaw) && digitsRaw >= 6 && digitsRaw <= 8) {
    digits = digitsRaw;
  }

  let algorithm: string = 'SHA1';
  const algorithmRaw: string | undefined = raw.algorithm;

  if ('string' === typeof algorithmRaw && ALGORITHMS.includes(algorithmRaw.toUpperCase())) {
    algorithm = algorithmRaw.toUpperCase();
  }

  const normalized: string = normalizeSecret(raw.secret);

  if (normalized.length === 0) {
    return invalidResult('secret 缺失');
  }

  let canonical: string;

  try {
    canonical = Secret.fromBase32(normalized, { strict: true }).toBase32();
  } catch (e) {
    return invalidResult('secret 不符合 Base32 规范');
  }

  const item: IBackupItem = {
    issuer: issuer,
    username: username,
    secret: canonical,
    period: period,
    digits: digits,
    algorithm: algorithm,
    tags: sanitizeTags(raw.tags),
    pinned: true === raw.pinned
  };

  return new SanitizeResult(true, item, '');
}

// 整体结构错误 → E_PAYLOAD；单条非法只记入 invalid，不阻塞整包（规范 §6）
export function parsePayload(text: string): PayloadParseResult {
  let parsed: Object | null = null;

  try {
    parsed = JSON.parse(text) as Object;
  } catch (e) {
    return new PayloadParseResult(false, [], [], BackupErrorCode.E_PAYLOAD, '明文不是 JSON');
  }

  if (null === parsed) {
    return new PayloadParseResult(false, [], [], BackupErrorCode.E_PAYLOAD, '明文不是对象');
  }

  const raw: IRawPayload = parsed as IRawPayload;

  if (1 !== raw.v) {
    return new PayloadParseResult(false, [], [], BackupErrorCode.E_PAYLOAD, 'payload.v 不为 1');
  }

  const items: IRawItem[] | undefined = raw.items;

  if ('undefined' === typeof items || !Array.isArray(items) || items.length > BackupSpec.MAX_ITEMS) {
    return new PayloadParseResult(false, [], [], BackupErrorCode.E_PAYLOAD, 'items 不是数组或超过上限');
  }

  const accepted: IBackupItem[] = [];
  const invalid: IInvalidItem[] = [];

  for (let i = 0; i < items.length; i++) {
    const result: SanitizeResult = sanitizeItem(items[i]);

    if (result.ok && 'undefined' !== typeof result.item) {
      accepted.push(result.item);
    } else {
      invalid.push({ index: i, reason: result.reason });
    }
  }

  return new PayloadParseResult(true, accepted, invalid, BackupErrorCode.E_PAYLOAD, '');
}

// 紧凑 JSON，字段顺序固定（规范 §6/§7）
export function stringifyPayload(items: IBackupItem[]): string {
  const rawItems: IRawItem[] = [];

  for (const item of items) {
    rawItems.push({
      issuer: item.issuer,
      username: item.username,
      secret: item.secret,
      period: item.period,
      digits: item.digits,
      algorithm: item.algorithm,
      tags: [...item.tags],
      pinned: item.pinned
    });
  }

  const payload: IRawPayload = {
    v: 1,
    items: rawItems
  };

  return JSON.stringify(payload);
}
