import { endpoint } from "@api/endpoint";
import { PATH, PLATFORM, THIRD_ID } from "@constant/access-token";
import { CODE } from "@constant/error";
import http from "@utils/http";
import type {
  LoginRefreshRequest,
  LoginRefreshResponse,
  LoginRequest,
  LoginResponse,
} from "types/access-token";

const login = endpoint(
  "登录接口请求失败",
  CODE.HTTP_API_ACCESS_TOKEN_LOGIN,
  (code: string) =>
    http.post<LoginResponse>(PATH.LOGIN, {
      platform: PLATFORM,
      third_id: THIRD_ID,
      code,
    } as LoginRequest),
);

const refresh = endpoint(
  "刷新令牌接口请求失败",
  CODE.HTTP_API_ACCESS_TOKEN_REFRESH,
  (refreshToken: string) =>
    http.post<LoginRefreshResponse>(PATH.REFRESH, {
      platform: PLATFORM,
      third_id: THIRD_ID,
      refresh_token: refreshToken,
    } as LoginRefreshRequest),
);

const valid = endpoint(
  "验证接口请求失败",
  CODE.HTTP_API_ACCESS_TOKEN_VALID,
  async (): Promise<boolean> => {
    await http.get<null>(PATH.VALID);

    return true;
  },
);

export default { login, refresh, valid };
