import userApi from "@api/user";
import { clearTokenBundle } from "@utils/app";
import error from "@utils/error";
import { notify } from "@utils/notify";
import { guardOnShow, guardOnUnlocked } from "@utils/page-guard";
import { clearDirty } from "@utils/security-sync";
import { clearCache } from "@utils/totp-cache";
import { clearUserCache } from "@utils/user-cache";
import { clearViewState } from "@utils/view-state";
import Toast, { hideToast } from "tdesign-miniprogram/toast/index";

interface CheckboxChangeEvent {
  detail: { checked: boolean };
}

Page({
  data: {
    locked: false,
    checked: false,
    dialogVisible: false,
    submitting: false,
  },
  onShow() {
    // 应用锁守卫：锁定时不发请求，直接渲染遮罩
    guardOnShow(this);
  },
  // 解锁成功：页面无取数/计时，仅解除锁定
  onUnlocked() {
    guardOnUnlocked(this);
  },
  onCheckChange(e: CheckboxChangeEvent) {
    this.setData({ checked: e.detail.checked === true });
  },
  onDeleteTap() {
    if (!this.data.checked || this.data.submitting) {
      return;
    }

    this.setData({ dialogVisible: true });
  },
  onDialogCancel() {
    this.setData({ dialogVisible: false });
  },
  async onDialogConfirm() {
    this.setData({ dialogVisible: false, submitting: true });

    Toast({
      message: "注销中...",
      theme: "loading",
      duration: 10000,
      direction: "column",
      preventScrollThrough: true,
    });

    try {
      await userApi.deleteUser();
    } catch (e) {
      this.setData({ submitting: false });
      hideToast();
      notify.error(this, `注销失败：${error.getErrorMessage(e)}`);

      return;
    }

    // 按序清理本地登录态 / TOTP 缓存 / 用户缓存 / 视图状态 / 安全脏标记（设备级设置保留）
    clearTokenBundle();
    clearCache();
    clearUserCache();
    clearViewState();
    clearDirty();

    await wx.reLaunch({ url: "/pages/totp/index" });
  },
});
