import api from "@api/user";
import { STORAGE } from "@constant/app";
import type { User } from "types/user";
import type { WxGetStorageSuccess } from "types/wechat";

const detail = async (): Promise<User> => {
  try {
    const storage: WxGetStorageSuccess<User> = await wx.getStorage({
      key: STORAGE.USER,
    });

    return storage.data;
  } catch (_e) {
    /* empty */
  }

  try {
    return await sync();
  } catch (_e) {
    /* empty */
  }

  return { phone: "", config: undefined };
};

const sync = async (): Promise<User> => {
  const detail = await api.detail();

  const user: User = {
    phone: detail.phone,
    config: detail.config,
  };

  wx.setStorageSync(STORAGE.USER, user);

  return user;
};

export default { detail, sync };
