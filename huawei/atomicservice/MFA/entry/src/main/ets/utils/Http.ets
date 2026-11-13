// HTTP 基础设施（纯网络层）：只负责 axios 配置、日志、错误归一。
//
// 本层**不 import** 模型 / 导航 / 提示等 UI 模块：
// - token 由启动期注入的 provider 提供（`configureHttp`）；
// - 认证失效只通过 `authExpired` 回调通知（由 `SessionGuard` 决定跳不跳登录页）。
// 这样网络层可以脱离 UI 复用 / 单测，也消除了 `Http ⇄ Nav/Models` 的循环依赖。
import axios, { AxiosError, AxiosResponse, InternalAxiosRequestConfig } from '@ohos/axios';
import { App, AppEnv, HttpDomain, LogDomain } from '../App';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { application } from '@kit.AbilityKit';
import { AuthExpiredError, ErrorKind, HttpError } from './Errors';
import { State } from '../types/Session';

export interface HttpAuthHooks {
  // 每次请求前取当前 access_token；无登录态返回 undefined
  token: () => string | undefined;
  // 认证失效（1000/1001/1002/1004/1005/1006）；由启动期注入，Http 不直接跳页面
  authExpired: (state: State) => void;
}

let _tokenProvider: (() => string | undefined) | undefined = undefined;
let _authExpiredHandler: ((state: State) => void) | undefined = undefined;

// 启动期（EntryAbility）注入一次；重复调用以最后一次为准
export const configureHttp = (hooks: HttpAuthHooks): void => {
  _tokenProvider = hooks.token;
  _authExpiredHandler = hooks.authExpired;
};

// 认证失效码：拦截器统一 reject 成 AuthExpiredError，业务层据此跳过「重试弹窗」
const CODE_REFRESH_EXPIRED: number[] = [1005, 1006];
const CODE_TOKEN_EXPIRED: number[] = [1000, 1001, 1002, 1004];

// 超时与其它网络错误分开提示：后端慢 / 网络差时用户能区分「超时」与「服务器错误」
const isTimeout = (e: AxiosError): boolean => {
  const code: string = e.code ?? '';
  const message: string = e.message ?? '';

  return 'ECONNABORTED' === code || 'ETIMEDOUT' === code || message.toLowerCase().includes('timeout');
};

const notifyAuthExpired = (state: State): void => {
  if ('undefined' === typeof _authExpiredHandler) {
    return;
  }

  try {
    _authExpiredHandler(state);
  } catch (e) {
    hilog.error(LogDomain.UTILS, 'utils/http', '认证失效回调执行失败: %{public}s', JSON.stringify(e));
  }
};

const url = (): string => {
  const env = App.env;

  if (AppEnv.TEST === env) {
    return HttpDomain.TEST;
  }

  return HttpDomain.PROD;
};

const http = axios.create();

http.defaults.baseURL = url();
http.defaults.timeout = 5000;
http.defaults.headers.common['Author'] = 'yansongda <me@yansongda.cn>';
http.defaults.headers.common['User-Agent'] = 'yansongda/atomicservice/MFA-v' + App.version + '-' + App.env;
http.defaults.headers.post['Content-Type'] = 'application/json';

http.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  const token: string | undefined = 'undefined' === typeof _tokenProvider ? undefined : _tokenProvider();

  if ('undefined' !== typeof token && token.length > 0) {
    config.headers['Authorization'] = token;
  }

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
        isTimeout(e) ? $r('app.string.error_http_timeout').id : $r('app.string.error_http_request_failed').id);
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
    notifyAuthExpired(State.REFRESH_TOKEN_EXPIRED);

    return Promise.reject(new AuthExpiredError(response.data?.message ?? '登录状态已失效，请重新登录', responseCode));
  }

  // token 过期
  if (CODE_TOKEN_EXPIRED.includes(responseCode)) {
    notifyAuthExpired(State.NEED_REFRESH);

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
