import type { RequestData } from "./http";

export interface Item {
  id: string;
  sort: number;
  issuer: string;
  username: string;
  code: string;
  config: ItemConfig;
}

export type TotpAlgorithm = "SHA1" | "SHA256" | "SHA512";

export interface ItemConfig {
  secret: string;
  period: number;
  // 后端净化后的验证码位数（6~8）与摘要算法（SHA1/SHA256/SHA512）；
  // 可选以兼容 PR #176 之前的旧后端响应，读取方按 6 / SHA1 兜底
  digits?: number;
  algorithm?: string;
}

export interface DetailRequest extends RequestData {
  id: string;
}

export interface EditIssuerRequest extends RequestData {
  id: string;
  issuer: string;
}

export interface EditUsernameRequest extends RequestData {
  id: string;
  username: string;
}

export interface CreateRequest extends RequestData {
  uri: string;
}

export interface DeleteRequest extends RequestData {
  id: string;
}

export interface ItemMessageEvent {
  detail: string;
}

export interface ItemDetailEvent {
  detail: string;
}

export interface ItemDeleteEvent {
  detail: string;
}

export interface CacheItem {
  id: string;
  issuer: string;
  username: string;
  secret: string;
  period: number;
  // 旧版本缓存（PR #176 之前）没有这两个字段：缺省 6 / SHA1 与当时后端强制值一致，无需清缓存
  digits?: number;
  algorithm?: string;
}

export interface TotpCache {
  items: CacheItem[];
}
