import { AppError } from "@models/error";

/**
 * 面向用户的错误文案：只有 `AppError` 的 message 视为产品文案；
 * 普通 Error 的内部信息（wx.* errMsg、英文调试信息）与第三方 OtpError 的
 * 英文码一律不展示，统一回落通用文案。
 */
const getErrorMessage = (e: unknown): string => {
  return e instanceof AppError ? e.message : "操作失败，请重试";
};

export default { getErrorMessage };
