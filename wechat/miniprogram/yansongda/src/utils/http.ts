import { PATH } from "@constant/access-token";
import { URL } from "@constant/app";
import { CODE, WECHAT_MESSAGE } from "@constant/error";
import { HttpError } from "@models/error";
import { getTokenBundle, refreshFallback, refreshToken } from "@utils/app";
import logger from "@utils/logger";
import type { Request, RequestData, RequestQuery, Response } from "types/http";
import type { WxRequestFail, WxRequestSuccess } from "types/wechat";

const { envVersion } = wx.getAccountInfoSync().miniProgram;

const AUTH_ENDPOINTS = [
  PATH.LOGIN,
  PATH.REFRESH,
  PATH.VALID,
] as readonly string[];

// Symbol cannot be serialized by JSON.stringify or spread-copy, so it never
// leaks into wx.request data/header even if cloneRequest misses a field.
const RETRY_MARKER = Symbol("retry");

// Deduplicates concurrent refresh attempts — only one refresh is in flight
// at any time; subsequent callers await the same promise.
let inFlightRefresh: Promise<unknown> | null = null;

// Login / refresh / valid endpoints must NOT trigger a recursive refresh
// when they themselves return 1004 — doing so would loop infinitely.
const isAuthEndpoint = (url: string): boolean =>
  AUTH_ENDPOINTS.some((ep) => url.includes(ep));

const formatUrl = (request: Request): void => {
  if (typeof request.query !== "undefined") {
    const query = request.query;

    const paramsArray: string[] = [];

    // biome-ignore lint: no-check
    Object.keys(request.query).forEach(
      (key) => query[key] && paramsArray.push(`${key}=${query[key]}`),
    );

    request.url += `${
      request.url.search(/\?/) === -1 ? "?" : "&"
    }${paramsArray.join("&")}`;
  }

  if (!request.url.startsWith("http")) {
    request.url = URL[envVersion] + request.url;
  }
};

const formatHeaders = (request: Request): void => {
  if (typeof request.headers === "undefined") {
    request.headers = {};
  }

  const accessToken = getTokenBundle().access_token;

  request.headers.authorization = accessToken ? `Bearer ${accessToken}` : "";
};

// Shallow-clone for mutation: formatUrl/formatHeaders mutate the original.
// Only copies JSON-safe properties — Symbol keys (like RETRY_MARKER) are
// intentionally excluded so they stay internal to the request lifecycle.
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

const handleTokenExpired = async <T>(
  originalRequest: Request,
  code: number,
  message: string,
): Promise<T> => {
  // Single-retry guard: if the marker is present, we already retried once
  // after a refresh — reject immediately to prevent an infinite loop.
  if ((originalRequest as Record<symbol, boolean>)[RETRY_MARKER]) {
    return Promise.reject(new HttpError(code, message));
  }

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
  // Mark this clone so a second 1004 from the retry is caught by the guard above.
  (retryRequest as Record<symbol, boolean>)[RETRY_MARKER] = true;

  return request<T>(retryRequest);
};

const request = <T>(req: Request): Promise<T> => {
  const preserved = cloneRequest(req);

  formatUrl(req);
  formatHeaders(req);

  if (req.isUploadFile) {
    return wxUpload(req, preserved);
  }

  return wxRequest(req, preserved);
};

const wxRequest = <T>(req: Request, preserved: Request) => {
  logger.info(
    "请求接口",
    req.url.indexOf("users/update") === -1 ? req : "用户更新",
  );

  return new Promise<T>((resolve, reject) => {
    wx.request({
      url: req.url,
      data: req.data || {},
      header: req.headers ?? {},
      timeout: req.timeout || 5000,
      method: req.method || "GET",
      success: (res: WxRequestSuccess<T>) => {
        logger.info(
          "接口请求成功",
          req.url.indexOf("users/detail") === -1 ? res : "用户详情",
        );

        if (Number(res.data.code) === 0) {
          resolve(res.data.data);
          return;
        }

        if (Number(res.data.code) === CODE.BACKEND_TOKEN_EXPIRED) {
          handleTokenExpired<T>(
            preserved,
            Number(res.data.code),
            res.data.message,
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

const wxUpload = <T>(req: Request, preserved: Request) => {
  logger.info("请求上传接口", req.url, req.headers);

  return new Promise<T>((resolve, reject) => {
    const filePath: string = (req.data?.filePath ?? "") as string;
    const name: string = (req.data?.name ?? "") as string;
    const formData = req.data ? { ...req.data } : {};

    if (!filePath || !name) {
      reject(new HttpError(CODE.HTTP_PARAMS));
      return;
    }

    formData.filePath = undefined;
    formData.name = undefined;

    wx.uploadFile({
      url: req.url,
      filePath,
      name,
      formData,
      header: req.headers ?? {},
      timeout: req.timeout || 30000,
      success: (res) => {
        logger.info("接口请求成功", res);

        const response = JSON.parse(res.data) as Response<T>;

        if (response.code === 0) {
          resolve(response.data);
          return;
        }

        if (Number(response.code) === CODE.BACKEND_TOKEN_EXPIRED) {
          handleTokenExpired<T>(
            preserved,
            Number(response.code),
            response.message,
          ).then(resolve, reject);
          return;
        }

        reject(new HttpError(Number(response.code), response.message));
      },
      fail: (err) => {
        logger.warning("接口请求失败", err);

        reject(new HttpError(undefined, `接口请求失败：${err.errMsg}`));
      },
    });
  });
};

const post = <T>(
  url: string,
  data?: RequestData,
  isUploadFile?: boolean,
): Promise<T> => {
  return request<T>({ url, data, isUploadFile, method: "POST" } as Request);
};

const get = <T>(url: string, query?: RequestQuery): Promise<T> => {
  return request<T>({ url, query, method: "GET" } as Request);
};

const upload = <T>(url: string, data?: RequestData): Promise<T> => {
  return request<T>({
    url,
    data,
    isUploadFile: true,
    method: "POST",
  } as Request);
};

export default { request, post, get, upload };
