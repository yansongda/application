import { CODE, MESSAGE } from "@constant/error";
import type { RequestData, RequestHeaders, RequestQuery } from "types/http";

export class EE {
  code: number;
  message: string;

  constructor(code?: number, message?: string) {
    this.code = code || CODE.UNKNOWN;
    this.message = message || MESSAGE[this.code] || MESSAGE[CODE.UNKNOWN];
  }
}

export class WeixinError extends EE {
  constructor(code?: number, message?: string) {
    super(code || CODE.WEIXIN, message);
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
  }
}
