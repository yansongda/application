import userApi from "../api/user";
import type { User } from "../types/user";
import logger from "./logger";
import { reconcile } from "./security-sync";
import { writeUserCache } from "./user-cache";

// 用户信息刷新：detail → 写本地缓存 → 调和端云安全设置；任何失败只记日志并返回 null（不打扰用户）。
const refreshUser = async (): Promise<User | null> => {
  try {
    const user = await userApi.detail();

    writeUserCache(user);
    await reconcile(user.config?.mfa?.security);

    return user;
  } catch (e: unknown) {
    logger.warning("刷新用户信息失败", e);

    return null;
  }
};

export { refreshUser };
