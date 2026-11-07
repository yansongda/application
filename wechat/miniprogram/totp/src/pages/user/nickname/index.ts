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
    nickname: "",
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
    this.setData({ nickname: readUserCache()?.config.nickname ?? "" });
  },
  onInput(e: InputEvent) {
    this.setData({ nickname: e.detail.value });
  },
  async onSave() {
    const nickname = this.data.nickname.trim();

    if (nickname.length === 0) {
      Message.error({
        content: "昵称不能为空",
        duration: 5000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    if (nickname.length > 16) {
      Message.error({
        content: "昵称最多 16 个字符",
        duration: 5000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    try {
      await userApi.editNickname(nickname);
    } catch (e) {
      Message.error({
        content: `保存失败：${error.getErrorMessage(e)}`,
        duration: 5000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    updateUserCache({ config: { nickname } });

    Toast({
      message: "昵称已更新",
      theme: "success",
      duration: 1500,
      direction: "column",
    });

    await wx.navigateBack();
  },
});
