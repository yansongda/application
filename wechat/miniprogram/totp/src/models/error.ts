import { CODE, MESSAGE } from "@constant/error";
import type { RequestData, RequestHeaders, RequestQuery } from "types/http";

/**
 * 自建错误统一基类：保留 Error 语义（stack / name / instanceof），code 域由子类决定。
 *
 * 微信编译器若把 class 降级到 ES5，`extends Error` 会丢原型链；`new.target`
 * 一次覆盖整条继承链（子类/孙类都成立）。
 *
 * 子类不得重声明 `code`：`target: esnext` 的 class field 会把基类构造器里的赋值
 * 重置成 undefined（TS 也会报 TS2612 / TS2564）。
 */
export abstract class AppError<C extends string | number> extends Error {
  readonly code: C;

  constructor(code: C, message: string) {
    super(message);
    Object.setPrototypeOf(this, new.target.prototype);
    this.code = code;
  }
}

export class EE extends AppError<number> {
  constructor(code?: number, message?: string) {
    const finalCode = code || CODE.UNKNOWN;
    super(finalCode, message || MESSAGE[finalCode] || MESSAGE[CODE.UNKNOWN]);
    this.name = "EE";
  }
}

export class WeixinError extends EE {
  constructor(code?: number, message?: string) {
    super(code || CODE.WEIXIN, message);
    this.name = "WeixinError";
  }
}

export class HttpError extends EE {
  url?: string;
  headers?: RequestHeaders;
  query?: RequestQuery;
  data?: RequestData;
  timeout?: number;

  constructor(code?: number, message?: string) {
    super(code || CODE.HTTP, message);
    this.name = "HttpError";
  }
}
