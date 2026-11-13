import { request } from './request';

export interface AccessTokenLoginRequest {
  platform: string;
  third_id: string;
  code: string;
}

export interface AccessTokenLoginResponse {
  access_token: string;
  expired_in: number;
  refresh_token: string;
}

export interface AccessTokenLoginRefreshRequest {
  platform: string;
  third_id: string;
  refresh_token: string;
}

export interface AccessTokenLoginRefreshResponse {
  access_token: string;
  expired_in: number;
  refresh_token: string;
}

export class AccessToken {
  static async login(clientId: string, authorizationCode: string): Promise<AccessTokenLoginResponse> {
    return request<AccessTokenLoginResponse, AccessTokenLoginRequest>('api/v1/access-token/login',
      {
        platform: 'HUAWEI',
        third_id: clientId,
        code: authorizationCode,
      });
  }

  static async loginRefresh(clientId: string, refreshToken: string): Promise<AccessTokenLoginRefreshResponse> {
    return request<AccessTokenLoginRefreshResponse, AccessTokenLoginRefreshRequest>('api/v1/access-token/login/refresh',
      {
        platform: 'HUAWEI',
        third_id: clientId,
        refresh_token: refreshToken,
      });
  }
}
