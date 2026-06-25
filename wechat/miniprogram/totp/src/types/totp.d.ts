import type { RequestData } from "./http";

export interface Item {
  id: string;
  sort: number;
  issuer: string;
  username: string;
  code: string;
  config: ItemConfig;
}

export interface ItemConfig {
  period: number;
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
