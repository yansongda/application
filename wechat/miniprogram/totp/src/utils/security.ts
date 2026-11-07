import { STORAGE } from "../constant/app";
import logger from "./logger";

// 安全设置本地存储：防截屏 / 应用锁开关 + 端云同步脏标记（华为 PrivacyWindow/AppLock 的持久化投影）。
// 运行态（locked / verifying / 退后台临时遮挡）绝不落盘，由 app-lock / privacy 模块持有。
export interface SecuritySettings {
  v: 1;
  privacyWindow: boolean;
  appLock: boolean;
  dirty: boolean;
}

export const DEFAULT_SECURITY_SETTINGS: SecuritySettings = {
  v: 1,
  privacyWindow: true,
  appLock: false,
  dirty: false,
};

// 归一化：非对象 / 缺字段 / 版本不符回落默认；dirty 以传入值为准（缺省 false），不得被清掉。
const normalizeSettings = (raw: unknown): SecuritySettings => {
  if (typeof raw !== "object" || raw === null) {
    return { ...DEFAULT_SECURITY_SETTINGS };
  }

  const obj = raw as Record<string, unknown>;

  if (obj.v !== 1) {
    return { ...DEFAULT_SECURITY_SETTINGS };
  }

  return {
    v: 1,
    privacyWindow:
      typeof obj.privacyWindow === "boolean"
        ? obj.privacyWindow
        : DEFAULT_SECURITY_SETTINGS.privacyWindow,
    appLock:
      typeof obj.appLock === "boolean"
        ? obj.appLock
        : DEFAULT_SECURITY_SETTINGS.appLock,
    dirty: typeof obj.dirty === "boolean" ? obj.dirty : false,
  };
};

const readSettings = (): SecuritySettings => {
  try {
    return normalizeSettings(wx.getStorageSync(STORAGE.SECURITY_SETTINGS));
  } catch (e: unknown) {
    logger.warning("读取安全设置失败", e);

    return { ...DEFAULT_SECURITY_SETTINGS };
  }
};

const writeSettings = (s: SecuritySettings): boolean => {
  try {
    wx.setStorageSync(STORAGE.SECURITY_SETTINGS, s);

    return true;
  } catch (e: unknown) {
    logger.warning("写入安全设置失败", e);

    return false;
  }
};

const markDirty = (): boolean => {
  return writeSettings({ ...readSettings(), dirty: true });
};

const clearDirty = (): boolean => {
  return writeSettings({ ...readSettings(), dirty: false });
};

export {
  clearDirty,
  markDirty,
  normalizeSettings,
  readSettings,
  writeSettings,
};
