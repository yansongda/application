import axios, { AxiosError, AxiosResponse, InternalAxiosRequestConfig } from '@ohos/axios';
import { App, AppEnv, HttpDomain, LogDomain } from '../App';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Authorization, State } from '../models/Auth';
import { PersistenceV2 } from '@kit.ArkUI';
import { application } from '@kit.AbilityKit';
import { redirectLoginPage } from './Nav';

const authorization =
  (): Authorization => PersistenceV2.globalConnect({ type: Authorization, defaultCreator: () => new Authorization() })!;
const url = (): string => {
  const env = App.env;

  if (AppEnv.TEST === env) {
    return HttpDomain.TEST;
  }

  return HttpDomain.PROD
}

const http = axios.create();

http.defaults.baseURL = url();
http.defaults.timeout = 5000;
http.defaults.headers.common['Author'] = 'yansongda <me@yansongda.cn>';
http.defaults.headers.common['User-Agent'] = 'yansongda/atomicservice/MFA-v' + App.version + '-' + App.env;
http.defaults.headers.post['Content-Type'] = 'application/json';

http.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  config.headers['Authorization'] = authorization().accessToken;

  // headers/请求体可能含 access token 等敏感信息，统一用 %{private}s 输出，避免落到日志
  hilog.info(LogDomain.UTILS, 'utils/http',
    '发送 http 请求，url: %{private}s, method: %{private}s, headers: %{private}s, request body: %{private}s', config.url,
    config.method,
    JSON.stringify(config.headers), JSON.stringify(config.data));

  return config;
}, (e: AxiosError) => {
  hilog.error(LogDomain.UTILS, 'utils/http',
    '发送 http 请求失败，message: %{private}s, url: %{private}s, method: %{private}s, headers: %{private}s, request body: %{private}s',
    e.message,
    e.config?.url, e.config?.method, JSON.stringify(e.config?.headers), JSON.stringify(e.config?.data));

  let message = '网络错误，请检查网络状态';

  try {
    message =
      application.getApplicationContext().resourceManager.getStringSync($r('app.string.error_http_request_failed').id)
  } catch (e) {
    hilog.warn(LogDomain.UTILS, 'utils/http', '获取请求失败提示文案失败: %{public}s', JSON.stringify(e));
  }

  return Promise.reject(new HttpError(message));
});

http.interceptors.response.use((response: AxiosResponse): AxiosResponse => {
  hilog.info(LogDomain.UTILS, 'utils/http',
    '接收 http 请求响应，url: %{private}s, method: %{private}s, response body: %{private}s, time: %{private}s',
    response.config.url,
    response.config.method, JSON.stringify(response.data), JSON.stringify(response.performanceTiming));

  const responseCode: number = response.data.code ?? -1;

  // refresh_token 过期
  if ([1005, 1006].includes(responseCode)) {
    redirectLoginPage(State.REFRESH_TOKEN_EXPIRED);
  }

  // token 过期
  if ([1000, 1001, 1002, 1004].includes(responseCode)) {
    redirectLoginPage(State.NEED_REFRESH);
  }

  return response;
}, (e: AxiosError) => {
  hilog.error(LogDomain.UTILS, 'utils/http',
    '接收 http 请求失败，code: %{private}s, message: %{private}s, url: %{private}s, method: %{private}s, request body: %{private}s, response body: %{private}s',
    e.code, e.message, e.config?.url, e.config?.method, JSON.stringify(e.config?.data), JSON.stringify(e.response?.data)
  );

  let message = '服务器响应错误，请重试或联系我们';

  try {
    message =
      application.getApplicationContext().resourceManager.getStringSync($r('app.string.error_http_response_failed').id)
  } catch (e) {
    hilog.warn(LogDomain.UTILS, 'utils/http', '获取响应失败提示文案失败: %{public}s', JSON.stringify(e));
  }

  return Promise.reject(new HttpError(message));
});

export interface Response<T> {
  code: number,
  message: string,
  data?: T,
}

export class HttpError extends Error {
}

export default http;