import accessToken from "@api/access-token";
import { STORAGE } from "@constant/app";
import type { LoginRefreshResponse, LoginResponse } from "types/access-token";
import type {
  WxGetUpdateManagerOnCheckForUpdateResult,
  WxLoginSuccessCallbackResult,
} from "types/wechat";
import logger from "./logger";

type TokenBundleResponse = LoginResponse | LoginRefreshResponse;

interface TokenBundle {
  access_token: string;
  refresh_token: string;
  expired_in: number;
  expired_at: number;
}

const getTokenBundle = (): TokenBundle => {
  const bundle = wx.getStorageSync(STORAGE.TOKEN_BUNDLE) as
    | TokenBundle
    | undefined;

  return {
    access_token: bundle?.access_token ?? "",
    refresh_token: bundle?.refresh_token ?? "",
    expired_in: bundle?.expired_in ?? 0,
    expired_at: bundle?.expired_at ?? 0,
  };
};

const saveTokenBundle = (response: TokenBundleResponse) => {
  if (!response.access_token) {
    throw new Error("saveTokenBundle: access_token is empty");
  }
  if (!response.refresh_token) {
    throw new Error("saveTokenBundle: refresh_token is empty");
  }
  if (typeof response.expired_in !== "number" || response.expired_in <= 0) {
    throw new Error("saveTokenBundle: expired_in must be a positive number");
  }

  const expired_at = Date.now() + response.expired_in * 1000;

  wx.setStorageSync(STORAGE.TOKEN_BUNDLE, {
    access_token: response.access_token,
    refresh_token: response.refresh_token,
    expired_in: response.expired_in,
    expired_at,
  });
};

const clearTokenBundle = () => {
  wx.removeStorageSync(STORAGE.TOKEN_BUNDLE);
};

const isAccessTokenFresh = (): boolean => {
  const bundle = getTokenBundle();

  // Requires all three fields — legacy storage that only has ACCESS_TOKEN
  // (no refresh_token / expired_at) is treated as incomplete, not valid.
  if (!bundle.access_token || !bundle.refresh_token || !bundle.expired_at) {
    return false;
  }

  return Date.now() < bundle.expired_at - 60_000;
};

const refreshToken = async (): Promise<LoginRefreshResponse> => {
  const bundle = getTokenBundle();
  const response = await accessToken.refresh(bundle.refresh_token);

  saveTokenBundle(response);

  return response;
};

const valid = async (): Promise<boolean> => {
  if (isAccessTokenFresh()) {
    return true;
  }

  const bundle = getTokenBundle();

  if (!bundle.refresh_token) {
    return false;
  }

  try {
    await refreshToken();
    return true;
  } catch {
    return false;
  }
};

const login = async () => {
  await wx.showToast({
    title: "登录中...",
    icon: "loading",
    duration: 6000,
    mask: true,
  });

  wx.login({
    success: async (res: WxLoginSuccessCallbackResult) => {
      try {
        const loginResponse: LoginResponse = await accessToken.login(res.code);

        saveTokenBundle(loginResponse);

        await wx.hideToast();
      } catch (e) {
        logger.error(e);

        restart("获取与设置基础信息失败，即将重启小程序", null);
      }
    },
    fail: () => {
      restart("微信登录 API 错误，即将重启小程序", null);
    },
  });
};

const restart = (
  content: string | null | undefined,
  path: string | null | undefined,
) => {
  wx.showModal({
    title: "提示",
    content: content ?? "小程序即将重启",
    showCancel: false,
    confirmText: "重启",
    success(res) {
      if (res.confirm) {
        wx.restartMiniProgram({ path: path ?? "/pages/home/index" });
      }
    },
  });
};

let fallbackPromise: Promise<void> | null = null;

const refreshFallback = (): Promise<void> => {
  if (fallbackPromise) {
    return fallbackPromise;
  }

  fallbackPromise = new Promise<void>((resolve, reject) => {
    clearTokenBundle();

    wx.showModal({
      title: "提示",
      content: "登录已过期，请重新登录",
      showCancel: true,
      confirmText: "重新登录",
      success(res) {
        if (res.confirm) {
          login();
          resolve();
        } else {
          reject(new Error("登录已过期，用户取消重新登录"));
        }
      },
      fail() {
        reject(new Error("登录弹窗调用失败"));
      },
    });
  }).finally(() => {
    fallbackPromise = null;
  });

  return fallbackPromise;
};

const upgrade = () => {
  const updateManager = wx.getUpdateManager();

  updateManager.onCheckForUpdate(
    (res: WxGetUpdateManagerOnCheckForUpdateResult) => {
      if (res.hasUpdate) {
        logger.info("小程序有最新版本，后续将自动更新");
      }
    },
  );

  updateManager.onUpdateReady(() => {
    wx.showModal({
      title: "更新提示",
      content: "新版本已经准备好，是否重启应用？",
      success(res) {
        if (res.confirm) {
          updateManager.applyUpdate();
        }
      },
    });
  });

  updateManager.onUpdateFailed(() => {
    logger.error("小程序更新下载异常");
  });
};

export {
  clearTokenBundle,
  getTokenBundle,
  isAccessTokenFresh,
  login,
  refreshFallback,
  refreshToken,
  valid,
};
export default { valid, login, restart, upgrade };
