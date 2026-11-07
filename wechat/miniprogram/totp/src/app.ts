// app.ts
import { ensureAuthenticated } from "@utils/app";
import {
  onHide as appLockOnHide,
  onLaunch as appLockOnLaunch,
  onShow as appLockOnShow,
} from "@utils/app-lock";
import { applyCurrent as applyPrivacy } from "@utils/privacy";
import { flush as flushSecuritySync } from "@utils/security-sync";
import type { AppOnUnhandledRejection } from "types/wechat";

App<IAppOption>({
  globalData: {},
  onLaunch() {
    wx.loadFontFace({
      family: "t",
      source: 'url("https://tdesign.gtimg.com/icon/0.4.2/fonts/t.ttf")',
    });

    // 安全设置落地：防截屏按本地存储值应用；应用锁复位冷启动状态
    applyPrivacy();
    appLockOnLaunch();

    // Warm-up only — do not await or gate other logic on it
    ensureAuthenticated();
  },
  onShow() {
    // 回前台：防截屏重新落地 + 应用锁挂起待检 + 安全设置脏标记上行
    applyPrivacy();
    appLockOnShow();
    flushSecuritySync();

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
  onHide() {
    appLockOnHide();
  },
  onError(e: string) {
    console.error("小程序异常", e);
  },
  onUnhandledRejection(e: AppOnUnhandledRejection) {
    console.error("未处理的 Promise 拒绝", e.reason);
  },
});
