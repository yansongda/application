import { PATH, PLATFORM, THIRD_ID } from "@constant/access-token";
import { CODE } from "@constant/error";
import { HttpError } from "@models/error";
import error from "@utils/error";
import http from "@utils/http";
import logger from "@utils/logger";
import type {
  LoginRefreshRequest,
  LoginRefreshResponse,
  LoginRequest,
  LoginResponse,
} from "types/access-token";

const login = async (code: string): Promise<LoginResponse> => {
  try {
    return await http.post<LoginResponse>(PATH.LOGIN, {
      platform: PLATFORM,
      third_id: THIRD_ID,
      code,
    } as LoginRequest);
  } catch (e: unknown) {
    logger.error("登录接口请求失败", e);

    throw new HttpError(
      CODE.HTTP_API_ACCESS_TOKEN_LOGIN,
      error.getErrorMessage(e),
    );
  }
};

const refresh = async (refreshToken: string): Promise<LoginRefreshResponse> => {
  try {
    return await http.post<LoginRefreshResponse>(PATH.REFRESH, {
      platform: PLATFORM,
      third_id: THIRD_ID,
      refresh_token: refreshToken,
    } as LoginRefreshRequest);
  } catch (e: unknown) {
    logger.error("刷新令牌接口请求失败", e);

    throw new HttpError(
      CODE.HTTP_API_ACCESS_TOKEN_REFRESH,
      error.getErrorMessage(e),
    );
  }
};

const valid = async (): Promise<boolean> => {
  try {
    await http.get<null>(PATH.VALID);

    return true;
  } catch (e: unknown) {
    logger.error("验证接口请求失败", e);

    throw new HttpError(
      CODE.HTTP_API_ACCESS_TOKEN_VALID,
      error.getErrorMessage(e),
    );
  }
};

export default { login, refresh, valid };
