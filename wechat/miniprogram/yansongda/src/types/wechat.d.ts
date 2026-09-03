import type { Response } from "./http";

export interface WxRequestSuccess<T> {
  data: Response<T>;
  statusCode: number;
  header: object;
}

export interface WxRequestFail {
  errno: number;
  errMsg: string;
}

export interface AppOnUnhandledRejection {
  /** 被拒绝的 Promise 对象 */
  // biome-ignore lint: 微信的提示，不改变
  promise: Promise<any>;
  /** 拒绝原因，一般是一个 Error 对象 */
  reason: Error | string;
}

export interface Tap<T, D> {
  type: string;
  currentTarget: {
    id: string;
    dataset: T;
  };
  target: {
    id: string;
    dataset: D;
  };
}

export interface FormSubmit<T> {
  detail: {
    formId: string;
    value: T;
  };
}

export interface ChooseAvatarButtonTap<T, D> extends Tap<T, D> {
  detail: {
    avatarUrl: string;
  };
}

export interface WxGetFileSystemManagerReadFileSuccess {
  data: string | ArrayBuffer;
}

export interface WxGetUpdateManagerOnCheckForUpdateResult {
  hasUpdate: boolean;
}

export interface WxLoginSuccessCallbackResult {
  code: string;
  errMsg: string;
}

export interface WxGetStorageSuccess<T> {
  data: T;
}

declare global {
  class URLSearchParams {
    append(name: string, value: string): void;
    toString(): string;
  }
}
