// 接口调用统一收口：所有 `api/*` 只声明路径/入参/出参，成功判定与错误构造集中在这里。
//
// 之前 20 个方法各自 `if (0 === code && data)` + `new HttpError(...)`，判定标准还不一致
// （create/detail 用 `data.id`、其余用 code）。统一后新增接口只需一行。
import { AxiosRequestConfig, AxiosResponse } from '@ohos/axios';
import http, { Response } from '../utils/Http';
import { HttpError } from '../utils/Errors';

// 响应体形状校验：后端约定 `{ code, message, data? }`。
// 网关 / 反向代理 / 路由错误页会返回 HTML 或纯文本（此时 `response.data` 是 string，`data.code` 为 undefined），
// 曾经用 `data?.code ?? -1` 兜底会把它当成「业务码 -1 的业务错误」，用户看到的是「请求失败」而不是
// 「服务器响应异常」——排查时也会被误导。这里显式区分：形状不对就是服务端问题，不带业务码。
const ensureEnvelope = <T>(response: AxiosResponse<Response<T>>): Response<T> => {
  const body: Response<T> = response.data;

  if ('undefined' === typeof body || null === body || 'number' !== typeof body.code) {
    throw new HttpError('服务器响应异常，请重试或联系我们');
  }

  return body;
};

// 业务码校验：非 0 一律抛 HttpError 并带上后端业务码（认证失效码已在 Http 拦截器里先 reject）
const ensureSuccess = <T>(response: AxiosResponse<Response<T>>): Response<T> => {
  const body: Response<T> = ensureEnvelope<T>(response);

  if (0 !== body.code) {
    throw new HttpError(body.message ?? '请求失败', body.code);
  }

  return body;
};

// 取出 data 并保证非空。注意这里**不带业务码**：此时 code 就是 0（成功），
// 带上去会在日志里出现「code=0 的错误」，排查时误导
const unwrap = <T>(body: Response<T>): T => {
  const data: T | undefined = body.data;

  // `data: null` 也算缺失：服务端可能显式返回 null 而不是省略字段
  if ('undefined' === typeof data || null === data) {
    throw new HttpError('响应数据缺失，请重试');
  }

  return data;
};

// 有响应体且有 data 的接口
export async function request<T, B>(path: string, body: B, config?: AxiosRequestConfig): Promise<T> {
  const response: AxiosResponse<Response<T>> =
    await http.post<T, AxiosResponse<Response<T>>, B>(path, body, config);

  return unwrap<T>(ensureSuccess<T>(response));
}

// 无请求体的接口。
// 必须传 `undefined` 而不是 `null`：`headers.post['Content-Type']` 是 application/json，
// axios 的 transformRequest 会把 `null` 序列化成字面量 `"null"` 发出去（4 字节 body），
// 改造前（不传 data）则是真正的空 body。当前后端不解析这几个接口的 body，但协议上不该悄悄改变。
export async function requestNoBody<T>(path: string, config?: AxiosRequestConfig): Promise<T> {
  const response: AxiosResponse<Response<T>> =
    await http.post<T, AxiosResponse<Response<T>>, undefined>(path, undefined, config);

  return unwrap<T>(ensureSuccess<T>(response));
}

// 有请求体、无响应 data 的接口（编辑 / 删除 / 排序）
export async function requestVoid<B>(path: string, body: B, config?: AxiosRequestConfig): Promise<void> {
  ensureSuccess<void>(await http.post<void, AxiosResponse<Response<void>>, B>(path, body, config));
}

// 无请求体、无响应 data 的接口
export async function requestVoidNoBody(path: string, config?: AxiosRequestConfig): Promise<void> {
  ensureSuccess<void>(await http.post<void, AxiosResponse<Response<void>>, undefined>(path, undefined, config));
}
