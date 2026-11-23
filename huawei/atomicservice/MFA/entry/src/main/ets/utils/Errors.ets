// 统一错误模型：网络层只产出两类错误——
// - `HttpError`：请求/服务端/业务码错误，可带后端业务码；
// - `AuthExpiredError`：认证失效（1000 系码），Http 拦截器已触发跳登录页，业务层据此跳过重试框与失败 toast。
//
// 本文件是叶子模块（不 import 任何业务模块），PromptAction / api / 页面都从这里取错误类型，
// 避免 `Http ⇔ PromptAction` 这类循环依赖。
//
// 注意：这里**不建错误分类枚举**。曾经有过 `ErrorKind`（network/timeout/server/auth/business），
// 但除了 `Http.ets` 在构造时赋值外没有任何读取方——分类体系没人用就只是噪音，
// 需要区分场景时请用 `instanceof AuthExpiredError` 或各自的错误文案。
export class HttpError extends Error {
  // 后端业务码（认证失效时为 1000 系码），无则为 undefined
  code?: number;

  constructor(message: string, code?: number) {
    super(message);
    this.code = code;
  }
}

// 认证失效（token 缺失 / 过期 / 非法）：Http 拦截器已负责触发跳转登录页，
// 业务层据此跳过「重试弹窗」与「失败 Toast」（否则会叠在登录页上方，形成弹窗来回跳）。
export class AuthExpiredError extends HttpError {
  constructor(message: string, code?: number) {
    super(message, code);
  }
}

// 捕获值归一：`catch (e)` 的静态类型是 Error，但运行时可能是 undefined / 字符串
// （历史代码里有过空 `Promise.reject()`）。在 catch 里读 message 前必须先归一，
// 否则会在错误处理里再抛一次 TypeError，把真实原因盖掉。
export const toError = (caught: Error): Error => {
  if (caught instanceof Error) {
    return caught;
  }

  return new Error('未知错误');
};

// 取可展示文案：非 Error 的捕获值退化为兜底文案
export const errorMessage = (caught: Error, fallback: string = '请求失败'): string => {
  const message: string = toError(caught).message;

  return message.length > 0 ? message : fallback;
};
