import { AxiosResponse } from '@ohos/axios';
import http, { HttpError, Response } from '../utils/Http';

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
    const response: AxiosResponse<Response<AccessTokenLoginResponse>> =
      await http.post<AccessTokenLoginResponse, AxiosResponse<Response<AccessTokenLoginResponse>>, AccessTokenLoginRequest>(
        'api/v1/access-token/login',
        {
          platform: "HUAWEI",
          third_id: clientId,
          code: authorizationCode
        });

    if (0 === response.data?.code && response.data?.data?.access_token) {
      return response.data.data;
    }

    return Promise.reject(new HttpError(response.data?.message ?? '请求失败'));
  }

  static async loginRefresh(clientId: string,
    refreshToken: string): Promise<AccessTokenLoginRefreshResponse> {
    const response: AxiosResponse<Response<AccessTokenLoginRefreshResponse>> =
      await http.post<AccessTokenLoginRefreshResponse, AxiosResponse<Response<AccessTokenLoginRefreshResponse>>, AccessTokenLoginRefreshRequest>(
        'api/v1/access-token/login/refresh',
        {
          platform: "HUAWEI",
          third_id: clientId,
          refresh_token: refreshToken
        });

    if (0 === response.data?.code && response.data?.data?.access_token) {
      return response.data.data;
    }

    return Promise.reject(new HttpError(response.data?.message ?? '请求失败'));
  }
}
