import type { RequestData } from "./http";

export interface LoginRequest extends RequestData {
  platform: string;
  third_id: string;
  code: string;
}

export interface LoginResponse {
  access_token: string;
  expired_in: number;
  refresh_token: string;
}

export interface LoginRefreshRequest extends RequestData {
  platform: string;
  third_id: string;
  refresh_token: string;
}

export interface LoginRefreshResponse {
  access_token: string;
  expired_in: number;
  refresh_token: string;
}
