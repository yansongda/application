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

export class AccessToken {
  static async login(clientId: string, authorizationCode: string): Promise<AccessTokenLoginResponse> {
    const response: AccessTokenLoginResponse =
      await request<AccessTokenLoginResponse, AccessTokenLoginRequest>('api/v1/access-token/login',
        {
          platform: 'HUAWEI',
          third_id: clientId,
          code: authorizationCode,
        });

    // 必填字段校验收在 assertUsable 里
    AccessToken.assertUsable(response.access_token, response.refresh_token, response.expired_in);

    return response;
  }

  static async loginRefresh(clientId: string, refreshToken: string): Promise<AccessTokenLoginResponse> {
    const response: AccessTokenLoginResponse =
      await request<AccessTokenLoginResponse, AccessTokenLoginRefreshRequest>(
        'api/v1/access-token/login/refresh',
        {
          platform: 'HUAWEI',
          third_id: clientId,
          refresh_token: refreshToken,
        });

    // 必填字段校验收在 assertUsable 里
    AccessToken.assertUsable(response.access_token, response.refresh_token, response.expired_in);

    return response;
  }

  // `code === 0` 不代表 data 可用：任一必填字段缺失都会让本地认证状态退化——
  // - access_token 空 → `state()` 变 EMPTY_AUTHORIZATION，表现为「登录成功却反复回登录页」；
  // - refresh_token 空 → 下次无法续期，同样退化成 EMPTY；
  // - expired_in 非数字 / 非正数 → `_expiredAt` 变 Invalid Date，5 分钟续期判定永远为 false。
  // 所以三个字段都在这里兜住。
  private static assertUsable(accessToken: string | undefined, refreshToken: string | undefined,
    expiredIn: number | undefined): void {
    if ('undefined' === typeof accessToken || 0 === accessToken.length ||
      'undefined' === typeof refreshToken || 0 === refreshToken.length ||
      'undefined' === typeof expiredIn || !Number.isFinite(expiredIn) || expiredIn <= 0) {
      throw new HttpError('登录响应异常，请重试');
    }
  }
}
