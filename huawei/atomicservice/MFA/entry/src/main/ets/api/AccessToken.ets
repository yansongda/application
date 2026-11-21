import { HttpError } from '../utils/Errors';
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
    const response: AccessTokenLoginResponse =
      await request<AccessTokenLoginResponse, AccessTokenLoginRequest>('api/v1/access-token/login',
        {
          platform: 'HUAWEI',
          third_id: clientId,
          code: authorizationCode,
        });

    // `code === 0` 不代表 data 里有 token：缺字段时直接失败，否则会把空 token 写进 Authorization，
    // 使 `state()` 退化成 EMPTY_AUTHORIZATION，表现为「登录成功却反复回到登录页」
    if ('undefined' === typeof response.access_token || 0 === response.access_token.length) {
      throw new HttpError('登录响应异常，请重试');
    }

    return response;
  }

  static async loginRefresh(clientId: string, refreshToken: string): Promise<AccessTokenLoginRefreshResponse> {
    const response: AccessTokenLoginRefreshResponse =
      await request<AccessTokenLoginRefreshResponse, AccessTokenLoginRefreshRequest>(
        'api/v1/access-token/login/refresh',
        {
          platform: 'HUAWEI',
          third_id: clientId,
          refresh_token: refreshToken,
        });

    // refresh 响应里的 refresh_token 也必填：缺失时要在这里就失败，
    // 否则本地 refresh_token 被写成 undefined，下次 `state()` 退化成 EMPTY/NEED_REFRESH
    if ('undefined' === typeof response.access_token || 0 === response.access_token.length ||
      'undefined' === typeof response.refresh_token || 0 === response.refresh_token.length) {
      throw new HttpError('登录响应异常，请重试');
    }

    return response;
  }
}
