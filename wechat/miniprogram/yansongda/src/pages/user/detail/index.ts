import { DEFAULT } from "@constant/user";
import { substr } from "@utils/string";
import user from "@utils/user";

Page({
  data: {
    config: {
      nickname: "",
      avatar: "",
      slogan: "",
    },
  },
  async onShow() {
    const u = await user.detail();

    this.setData({
      config: {
        nickname: substr(u.config?.nickname ?? DEFAULT.CONFIG.NICKNAME),
        avatar: u.config?.avatar ?? DEFAULT.CONFIG.AVATAR,
        slogan: substr(u.config?.slogan ?? DEFAULT.CONFIG.SLOGAN),
      },
    });
  },
  async editAvatar() {
    await wx.navigateTo({ url: "/pages/user/edit/avatar" });
  },
});
