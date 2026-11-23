import axios, { AxiosError, AxiosResponse, InternalAxiosRequestConfig } from '@ohos/axios';
import { App, AppEnv, HttpDomain, LogDomain } from '../App';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Authorization, State } from '../models/Auth';
import { PersistenceV2 } from '@kit.ArkUI';
import { application } from '@kit.AbilityKit';
import { redirectLoginPage } from './Nav';
import { AuthExpiredError, ErrorKind, HttpError } from './Errors';

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

// 认证失效码：拦截器统一跳登录页并 reject 成 AuthExpiredError，
// 业务层据此跳过「重试弹窗」（否则会在登录页上再叠一层重试框）。
const CODE_REFRESH_EXPIRED: number[] = [1005, 1006];
const CODE_TOKEN_EXPIRED: number[] = [1000, 1001, 1002, 1004];

// 超时与其它网络错误分开提示：后端慢 / 网络差时用户能区分「超时」与「服务器错误」
const isTimeout = (e: AxiosError): boolean => {
  const code: string = e.code ?? '';
  const message: string = e.message ?? '';

  return 'ECONNABORTED' === code || 'ETIMEDOUT' === code || message.toLowerCase().includes('timeout');
};

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
      application.getApplicationContext().resourceManager.getStringSync(
        isTimeout(e) ? $r('app.string.error_http_timeout').id : $r('app.string.error_http_request_failed').id)
  } catch (error) {
    hilog.warn(LogDomain.UTILS, 'utils/http', '获取请求失败提示文案失败: %{public}s', JSON.stringify(error));
  }

  return Promise.reject(new HttpError(message, undefined,
    isTimeout(e) ? ErrorKind.TIMEOUT : ErrorKind.NETWORK));
});

http.interceptors.response.use((response: AxiosResponse) => {
  hilog.info(LogDomain.UTILS, 'utils/http',
    '接收 http 请求响应，url: %{private}s, method: %{private}s, response body: %{private}s, time: %{private}s',
    response.config.url,
    response.config.method, JSON.stringify(response.data), JSON.stringify(response.performanceTiming));

  const responseCode: number = response.data.code ?? -1;

  // refresh_token 过期
  if (CODE_REFRESH_EXPIRED.includes(responseCode)) {
    redirectLoginPage(State.REFRESH_TOKEN_EXPIRED);

    return Promise.reject(new AuthExpiredError(response.data?.message ?? '登录状态已失效，请重新登录', responseCode));
  }

  // token 过期
  if (CODE_TOKEN_EXPIRED.includes(responseCode)) {
    redirectLoginPage(State.NEED_REFRESH);

    return Promise.reject(new AuthExpiredError(response.data?.message ?? '登录状态已失效，请重新登录', responseCode));
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
      application.getApplicationContext().resourceManager.getStringSync(
        isTimeout(e) ? $r('app.string.error_http_timeout').id : $r('app.string.error_http_response_failed').id)
  } catch (error) {
    hilog.warn(LogDomain.UTILS, 'utils/http', '获取响应失败提示文案失败: %{public}s', JSON.stringify(error));
  }

  return Promise.reject(new HttpError(message, undefined,
    isTimeout(e) ? ErrorKind.TIMEOUT : ErrorKind.SERVER));
});

export interface Response<T> {
  code: number,
  message: string,
  data?: T,
}

export default http;
