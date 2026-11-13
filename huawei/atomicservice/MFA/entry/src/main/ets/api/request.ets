// 接口调用统一收口：所有 `api/*` 只声明路径/入参/出参，成功判定与错误构造集中在这里。
//
// 之前 20 个方法各自 `if (0 === code && data)` + `new HttpError(...)`，判定标准还不一致
// （create/detail 用 `data.id`、其余用 code）。统一后新增接口只需一行。
import { AxiosRequestConfig, AxiosResponse } from '@ohos/axios';
import http, { Response } from '../utils/Http';
import { HttpError } from '../utils/Errors';

const unwrap = <T>(response: AxiosResponse<Response<T>>, withData: boolean): T | undefined => {
  const code: number = response.data?.code ?? -1;

  if (0 !== code) {
    throw new HttpError(response.data?.message ?? '请求失败', code);
  }

  if (withData && ('undefined' === typeof response.data.data || null === response.data.data)) {
    throw new HttpError(response.data?.message ?? '请求失败', code);
  }

  return response.data.data;
};

// 有响应体且有 data 的接口
export async function request<T, B>(path: string, body: B, config?: AxiosRequestConfig): Promise<T> {
  const response: AxiosResponse<Response<T>> =
    await http.post<T, AxiosResponse<Response<T>>, B>(path, body, config);
  const data: T | undefined = unwrap<T>(response, true);

  if ('undefined' === typeof data) {
    throw new HttpError('请求失败');
  }

  return data;
}

// 无请求体的接口
export async function requestNoBody<T>(path: string, config?: AxiosRequestConfig): Promise<T> {
  const response: AxiosResponse<Response<T>> =
    await http.post<T, AxiosResponse<Response<T>>, null>(path, null, config);
  const data: T | undefined = unwrap<T>(response, true);

  if ('undefined' === typeof data) {
    throw new HttpError('请求失败');
  }

  return data;
}

// 有请求体、无响应 data 的接口（编辑 / 删除 / 排序）
export async function requestVoid<B>(path: string, body: B, config?: AxiosRequestConfig): Promise<void> {
  const response: AxiosResponse<Response<void>> =
    await http.post<void, AxiosResponse<Response<void>>, B>(path, body, config);

  unwrap<void>(response, false);
}

// 无请求体、无响应 data 的接口
export async function requestVoidNoBody(path: string, config?: AxiosRequestConfig): Promise<void> {
  const response: AxiosResponse<Response<void>> =
    await http.post<void, AxiosResponse<Response<void>>, null>(path, null, config);

  unwrap<void>(response, false);
}
