import { PATH } from "@constant/access-token";
import { URL } from "@constant/app";
import { CODE, WECHAT_MESSAGE } from "@constant/error";
import { HttpError } from "@models/error";
import { clearTokenBundle, getTokenBundle, refreshToken } from "@utils/app";
import logger from "@utils/logger";
import type { Request, RequestData, RequestQuery } from "types/http";
import type { WxRequestFail, WxRequestSuccess } from "types/wechat";

const { envVersion } = wx.getAccountInfoSync().miniProgram;

const AUTH_ENDPOINTS = [
  PATH.LOGIN,
  PATH.REFRESH,
  PATH.VALID,
] as readonly string[];

const REFRESH_TRIGGER_CODES: readonly number[] = [
  CODE.BACKEND_AUTH_HEADER_MISSING,
  CODE.BACKEND_AUTH_TOKEN_INVALID,
  CODE.BACKEND_AUTH_FORMAT_INVALID,
  CODE.BACKEND_TOKEN_EXPIRED,
];

// Deduplicates concurrent refresh attempts — only one refresh is in flight
// at any time; subsequent callers await the same promise.
let inFlightRefresh: Promise<unknown> | null = null;

// Login / refresh / valid endpoints must NOT trigger a recursive refresh
// when they themselves return an auth trigger code — doing so would loop infinitely.
const isAuthEndpoint = (url: string): boolean => {
  const pathOnly = url.split("?", 1)[0];

  return AUTH_ENDPOINTS.some((ep) => pathOnly.endsWith(ep));
};

const formatUrl = (req: Request): void => {
  if (typeof req.query !== "undefined") {
    const parts: string[] = [];

    for (const key of Object.keys(req.query)) {
      const value = req.query[key];

      if (value !== null && value !== undefined && value !== "") {
        parts.push(
          `${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`,
        );
      }
    }

    if (parts.length > 0) {
      req.url += `${req.url.search(/\?/) === -1 ? "?" : "&"}${parts.join("&")}`;
    }
  }

  if (!req.url.startsWith("http")) {
    req.url = URL[envVersion] + req.url;
  }
};

const formatHeaders = (req: Request): void => {
  if (typeof req.headers === "undefined") {
    req.headers = {};
  }

  const bundle = getTokenBundle();
  const accessToken = bundle?.access_token;

  req.headers.authorization = accessToken ? `Bearer ${accessToken}` : "";
};

// Shallow-clone for mutation: formatUrl/formatHeaders mutate the original.
const cloneRequest = (req: Request): Request => ({
  url: req.url,
  query: req.query ? { ...req.query } : undefined,
  data: req.data ? { ...req.data } : undefined,
  headers: req.headers ? { ...req.headers } : undefined,
  method: req.method,
  timeout: req.timeout,
  isUploadFile: req.isUploadFile,
});

const ensureSingleFlightRefresh = (): Promise<unknown> => {
  if (!inFlightRefresh) {
    inFlightRefresh = refreshToken()
      .catch((err) => {
        logger.warning("token 刷新失败", err);
        throw err;
      })
      .finally(() => {
        inFlightRefresh = null;
      });
  }

  return inFlightRefresh;
};

// When the refresh itself fails, clear the token bundle so the next
// call to ensureAuthenticated() triggers a full wx.login flow.
const refreshFallback = (): Promise<void> => {
  clearTokenBundle();

  return Promise.reject(new Error("token 刷新回退：已清除本地令牌"));
};

const handleTokenExpired = async <T>(
  originalRequest: Request,
  code: number,
  message: string,
  isRetry?: boolean,
): Promise<T> => {
  // Single-retry guard: if we already retried once after a refresh —
  // reject immediately to prevent an infinite loop.
  if (isRetry) {
    return Promise.reject(new HttpError(code, message));
  }

  // Auth endpoints must NOT trigger a recursive refresh — reject directly.
  if (isAuthEndpoint(originalRequest.url)) {
    return Promise.reject(new HttpError(code, message));
  }

  try {
    await ensureSingleFlightRefresh();
  } catch {
    await refreshFallback().catch(() => {});

    return Promise.reject(new HttpError(code, message));
  }

  const retryRequest = cloneRequest(originalRequest);

  return request<T>(retryRequest, { isRetry: true });
};

const request = <T>(
  req: Request,
  opts: { isRetry?: boolean } = {},
): Promise<T> => {
  const preserved = cloneRequest(req);

  formatUrl(req);
  formatHeaders(req);

  return wxRequest<T>(req, preserved, opts);
};

const wxRequest = <T>(
  req: Request,
  preserved: Request,
  opts: { isRetry?: boolean } = {},
): Promise<T> => {
  logger.info("请求接口", req.url);

  return new Promise<T>((resolve, reject) => {
    wx.request({
      url: req.url,
      data: req.data || {},
      header: req.headers ?? {},
      timeout: req.timeout || 5000,
      method: req.method || "GET",
      success: (res: WxRequestSuccess<T>) => {
        if (Number(res.data.code) === 0) {
          resolve(res.data.data);
          return;
        }

        if (REFRESH_TRIGGER_CODES.includes(Number(res.data.code))) {
          handleTokenExpired<T>(
            preserved,
            Number(res.data.code),
            res.data.message,
            opts.isRetry,
          ).then(resolve, reject);
          return;
        }

        reject(new HttpError(Number(res.data.code), res.data.message));
      },
      fail: (err: WxRequestFail) => {
        logger.warning("接口请求失败", err);

        reject(
          new HttpError(
            err.errno,
            WECHAT_MESSAGE[err.errno as keyof typeof WECHAT_MESSAGE] ||
              `接口请求失败：${err.errMsg}`,
          ),
        );
      },
    });
  });
};

const post = <T>(url: string, data?: RequestData): Promise<T> => {
  return request<T>({ url, data, method: "POST" } as Request);
};

const get = <T>(url: string, query?: RequestQuery): Promise<T> => {
  return request<T>({ url, query, method: "GET" } as Request);
};

export default { request, post, get };
