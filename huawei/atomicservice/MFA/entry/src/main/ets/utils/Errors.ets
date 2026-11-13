// 统一错误模型：网络层只产出「可分类」的错误，UI 层按 kind 决定提示方式与是否重试。
//
// 本文件是叶子模块（不 import 任何业务模块），PromptAction / api / 页面都从这里取错误类型，
// 避免 `Http ⇄ PromptAction` 这类循环依赖。新增错误类别时只在这里加枚举值。
export enum ErrorKind {
  // 请求未到达服务端（断网、DNS、连接被拒）
  NETWORK = 'network',
  // 请求超时（axios 的 ECONNABORTED / ETIMEDOUT / message 含 timeout）
  TIMEOUT = 'timeout',
  // 服务端响应异常（5xx / 网关错误）
  SERVER = 'server',
  // 认证失效（后端 1000/1001/1002/1004/1005/1006）：Http 拦截器已触发跳登录页
  AUTH = 'auth',
  // 业务错误（后端返回非 0 业务码）
  BUSINESS = 'business',
}

export class HttpError extends Error {
  // 后端业务码（认证失效时为 1000 系码），无则为 undefined
  code?: number;

  // 错误分类：调用方按 kind 分支，不要依赖 message 文案
  kind: ErrorKind;

  constructor(message: string, code?: number, kind: ErrorKind = ErrorKind.BUSINESS) {
    super(message);
    this.code = code;
    this.kind = kind;
  }
}

// 认证失效（token 缺失 / 过期 / 非法）：Http 拦截器已负责触发跳转登录页，
// 业务层据此跳过「重试弹窗」与「失败 Toast」（否则会叠在登录页上方，形成弹窗来回跳）。
export class AuthExpiredError extends HttpError {
  constructor(message: string, code?: number) {
    super(message, code, ErrorKind.AUTH);
  }
}
