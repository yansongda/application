// 接口调用统一收口：所有 `api/*` 只声明路径/入参/出参，成功判定与错误构造集中在这里。
//
// 之前 20 个方法各自 `if (0 === code && data)` + `new HttpError(...)`，判定标准还不一致
// （create/detail 用 `data.id`、其余用 code）。统一后新增接口只需一行。
import { AxiosRequestConfig, AxiosResponse } from '@ohos/axios';
import http, { Response } from '../utils/Http';
import { HttpError } from '../utils/Errors';

// 业务码校验：非 0 一律抛 HttpError 并带上后端业务码（认证失效码已在 Http 拦截器里先 reject）
const ensureSuccess = <T>(response: AxiosResponse<Response<T>>): void => {
  const code: number = response.data?.code ?? -1;

  if (0 !== code) {
    throw new HttpError(response.data?.message ?? '请求失败', code);
  }
};

// 取出 data 并保证非空。注意这里**不带业务码**：此时 code 就是 0（成功），
// 带上去会在日志里出现「code=0 的错误」，排查时误导
const unwrap = <T>(response: AxiosResponse<Response<T>>): T => {
  ensureSuccess<T>(response);

  const data: T | undefined = response.data.data;

  // `data: null` 也算缺失：服务端可能显式返回 null 而不是省略字段
  if ('undefined' === typeof data || null === data) {
    throw new HttpError(response.data?.message ?? '响应数据缺失，请重试');
  }

  return data;
};

// 有响应体且有 data 的接口
export async function request<T, B>(path: string, body: B, config?: AxiosRequestConfig): Promise<T> {
  const response: AxiosResponse<Response<T>> =
    await http.post<T, AxiosResponse<Response<T>>, B>(path, body, config);

  return unwrap<T>(response);
}

// 无请求体的接口
export async function requestNoBody<T>(path: string, config?: AxiosRequestConfig): Promise<T> {
  const response: AxiosResponse<Response<T>> =
    await http.post<T, AxiosResponse<Response<T>>, null>(path, null, config);

  return unwrap<T>(response);
}

// 有请求体、无响应 data 的接口（编辑 / 删除 / 排序）
export async function requestVoid<B>(path: string, body: B, config?: AxiosRequestConfig): Promise<void> {
  ensureSuccess<void>(await http.post<void, AxiosResponse<Response<void>>, B>(path, body, config));
}

// 无请求体、无响应 data 的接口
export async function requestVoidNoBody(path: string, config?: AxiosRequestConfig): Promise<void> {
  ensureSuccess<void>(await http.post<void, AxiosResponse<Response<void>>, null>(path, null, config));
}
