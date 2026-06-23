import { PATH } from "@constant/access-token";
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

const { appId } = wx.getAccountInfoSync().miniProgram;

const login = async (code: string) => {
  try {
    return await http.post<LoginResponse>(PATH.LOGIN, {
      platform: "wechat",
      third_id: appId,
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

const refresh = async (refreshToken: string) => {
  try {
    return await http.post<LoginRefreshResponse>(PATH.REFRESH, {
      platform: "wechat",
      third_id: appId,
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

const valid = async () => {
  try {
    return await http.get<null>(PATH.VALID);
  } catch (e: unknown) {
    logger.error("验证接口请求失败", e);

    throw new HttpError(
      CODE.HTTP_API_ACCESS_TOKEN_VALID,
      error.getErrorMessage(e),
    );
  }
};

export default { login, refresh, valid };
