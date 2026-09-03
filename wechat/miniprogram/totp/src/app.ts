// app.ts
import { ensureAuthenticated } from "@utils/app";
import type { AppOnUnhandledRejection } from "types/wechat";

App<IAppOption>({
  globalData: {},
  onLaunch() {
    wx.loadFontFace({
      family: "t",
      source: 'url("https://tdesign.gtimg.com/icon/0.4.2/fonts/t.ttf")',
    });

    // Warm-up only — do not await or gate other logic on it
    ensureAuthenticated();
  },
  onShow() {
    const updateManager = wx.getUpdateManager();

    updateManager.onCheckForUpdate((res) => {
      if (res.hasUpdate) {
        console.info("小程序有最新版本，后续将自动更新");
      }
    });

    updateManager.onUpdateReady(() => {
      wx.showModal({
        title: "更新提示",
        content: "新版本已经准备好，是否重启应用？",
        success(res) {
          if (res.confirm) {
            updateManager.applyUpdate();
          }
        },
      });
    });

    updateManager.onUpdateFailed(() => {
      console.error("小程序更新下载异常");
    });
  },
  onError(e: string) {
    console.error("小程序异常", e);
  },
  onUnhandledRejection(e: AppOnUnhandledRejection) {
    console.error("未处理的 Promise 拒绝", e.reason);
  },
});
