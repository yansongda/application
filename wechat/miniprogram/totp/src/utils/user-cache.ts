import { STORAGE } from "../constant/app";
import type { User, UserCache } from "../types/user";
import logger from "./logger";

// 归一化文本字段：空串 / 非字符串 → undefined（不落盘）。
const normalizeText = (value: unknown): string | undefined => {
  if (typeof value === "string" && value !== "") {
    return value;
  }

  return undefined;
};

// 归一化用户资料：非对象 → null；只保留 phone 与 config.avatar/nickname/slogan，丢弃 mfa（安全设置独立存储键）。
const normalizeUserCache = (raw: unknown): UserCache | null => {
  if (typeof raw !== "object" || raw === null) {
    return null;
  }

  const obj = raw as Record<string, unknown>;
  const config = obj.config;

  if (typeof config !== "object" || config === null) {
    return null;
  }

  const cfg = config as Record<string, unknown>;

  return {
    phone: normalizeText(obj.phone),
    config: {
      avatar: normalizeText(cfg.avatar),
      nickname: normalizeText(cfg.nickname),
      slogan: normalizeText(cfg.slogan),
    },
  };
};

const readUserCache = (): UserCache | null => {
  try {
    return normalizeUserCache(wx.getStorageSync(STORAGE.USER_CACHE));
  } catch (e: unknown) {
    logger.warning("读取用户缓存失败", e);

    return null;
  }
};

const writeUserCache = (user: User): boolean => {
  const cache = normalizeUserCache(user);

  if (cache === null) {
    return false;
  }

  try {
    wx.setStorageSync(STORAGE.USER_CACHE, cache);

    return true;
  } catch (e: unknown) {
    logger.warning("写入用户缓存失败", e);

    return false;
  }
};

interface UserCachePatch {
  phone?: string | null;
  config?: {
    avatar?: string | null;
    nickname?: string | null;
    slogan?: string | null;
  };
}

const updateUserCache = (patch: UserCachePatch): boolean => {
  const current: UserCache = readUserCache() ?? { config: {} };
  const applyText = (
    next: unknown,
    prev?: string | null,
  ): string | undefined => {
    if (typeof next === "string" && next !== "") {
      return next;
    }

    return prev ?? undefined;
  };

  const next: UserCache = {
    phone: applyText(patch.phone, current.phone),
    config: {
      avatar: applyText(patch.config?.avatar, current.config.avatar),
      nickname: applyText(patch.config?.nickname, current.config.nickname),
      slogan: applyText(patch.config?.slogan, current.config.slogan),
    },
  };

  try {
    wx.setStorageSync(STORAGE.USER_CACHE, next);

    return true;
  } catch (e: unknown) {
    logger.warning("更新用户缓存失败", e);

    return false;
  }
};

const clearUserCache = (): void => {
  try {
    wx.removeStorageSync(STORAGE.USER_CACHE);
  } catch (e: unknown) {
    logger.warning("清除用户缓存失败", e);
  }
};

export {
  clearUserCache,
  normalizeUserCache,
  readUserCache,
  updateUserCache,
  writeUserCache,
};
