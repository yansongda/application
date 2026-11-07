import api from "@api/totp";
import { syncOnPageShow as appLockSyncOnPageShow } from "@utils/app-lock";
import error from "@utils/error";
import { withLoading } from "@utils/loading";
import { updateItemFields } from "@utils/totp-cache";
import Message from "tdesign-miniprogram/message/index";
import Toast from "tdesign-miniprogram/toast/index";
import type { EditIssuerRequest } from "types/totp";
import type { FormSubmit } from "types/wechat";

interface Query {
  id?: string;
  issuer?: string;
}

interface FormData {
  issuer: string;
}

Page({
  data: {
    locked: false,
    id: "0",
    issuer: "",
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
  onLoad(query: Query) {
    this.setData({
      id: query.id || "0",
      issuer: query.issuer ? decodeURIComponent(query.issuer) : "",
    });
  },
  async submit(e: FormSubmit<FormData>) {
    const issuer = e.detail.value.issuer.trim();

    // 空值不提交：提示后返回，不发请求。
    if (issuer.length === 0) {
      Toast({
        message: "提供商名称不能为空",
        theme: "error",
        duration: 1500,
        direction: "column",
      });

      return;
    }

    try {
      await withLoading("更新中...", () =>
        api.editIssuer({
          id: this.data.id,
          issuer,
        } as EditIssuerRequest),
      );

      updateItemFields(this.data.id, { issuer });

      Toast({
        message: "修改成功",
        theme: "success",
        duration: 1500,
        direction: "column",
        preventScrollThrough: true,
      });

      setTimeout(() => wx.navigateBack(), 1500);
    } catch (e: unknown) {
      Toast({
        message: "更新失败",
        theme: "error",
        duration: 100,
        direction: "column",
      });

      Message.error({
        content: `更新失败：${error.getErrorMessage(e)}`,
        duration: 5000,
        context: this,
        offset: [20, 32],
      });
    }
  },
  async cancel() {
    await wx.navigateBack();
  },
});
