export interface Request {
  url: string;
  query?: RequestQuery;
  data?: RequestData;
  headers?: RequestHeaders;
  method?:
    | "POST"
    | "OPTIONS"
    | "GET"
    | "HEAD"
    | "PUT"
    | "DELETE"
    | "TRACE"
    | "CONNECT"
    | undefined;
  timeout?: number;
  isUploadFile?: boolean;
}

export interface RequestQuery {
  [key: string]: number | string;
}

export interface RequestData {
  [key: string]:
    | number
    | string
    | object
    | number[]
    | string[]
    | object[]
    | undefined;
}

export interface RequestHeaders {
  [key: string]: number | string;
}

export interface Response<T> {
  code: number | string;
  message: string;
  data: T;
}
