import { MESSAGE } from "@constant/error";
import { EE } from "@models/error";
import app from "@utils/app";
import logger from "@utils/logger";
import type { AppOnUnhandledRejection } from "types/wechat";

App({
  async onLaunch() {
    wx.loadFontFace({
      family: "t",
      source: 'url("https://tdesign.gtimg.com/icon/0.4.2/fonts/t.ttf")',
    });

    const valid = await app.valid();

    if (!valid) {
      await app.login();
    }
  },
  onShow() {
    app.upgrade();
  },
  async onError(e: string) {
    logger.error("小程序异常", e);

    await wx.showToast({ title: "小程序异常", icon: "error" });
  },
  async onUnhandledRejection(e: AppOnUnhandledRejection) {
    if (e.reason instanceof EE) {
      await wx.showToast({ title: MESSAGE[e.reason.code], icon: "error" });

      return;
    }

    logger.error("未知错误", e);

    await wx.showToast({ title: "出现未知错误", icon: "error" });
  },
});
