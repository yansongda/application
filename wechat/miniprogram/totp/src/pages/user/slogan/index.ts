import userApi from "@api/user";
import { syncOnPageShow as appLockSyncOnPageShow } from "@utils/app-lock";
import error from "@utils/error";
import { readUserCache, updateUserCache } from "@utils/user-cache";
import Message from "tdesign-miniprogram/message/index";
import Toast from "tdesign-miniprogram/toast/index";

interface InputEvent {
  detail: { value: string };
}

Page({
  data: {
    locked: false,
    slogan: "",
  },
  onShow() {
    // 应用锁守卫：锁定时不发请求，直接渲染遮罩
    const locked = appLockSyncOnPageShow();

    if (locked !== this.data.locked) {
      this.setData({ locked });
    }

    if (locked) {
      return;
    }
  },
  // 解锁成功：页面无取数/计时，仅解除锁定
  onUnlocked() {
    this.setData({ locked: false });
  },
  onLoad() {
    this.setData({ slogan: readUserCache()?.config.slogan ?? "" });
  },
  onInput(e: InputEvent) {
    this.setData({ slogan: e.detail.value });
  },
  async onSave() {
    const slogan = this.data.slogan.trim();

    if (slogan.length <= 3) {
      Message.error({
        content: "Slogan 至少 4 个字符",
        duration: 5000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    if (slogan.length > 128) {
      Message.error({
        content: "Slogan 最多 128 个字符",
        duration: 5000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    try {
      await userApi.editSlogan(slogan);
    } catch (e) {
      Message.error({
        content: `保存失败：${error.getErrorMessage(e)}`,
        duration: 5000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    updateUserCache({ config: { slogan } });

    Toast({
      message: "Slogan 已更新",
      theme: "success",
      duration: 1500,
      direction: "column",
    });

    await wx.navigateBack();
  },
});
