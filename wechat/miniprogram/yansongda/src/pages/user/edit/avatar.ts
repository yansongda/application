import api from "@api/user";
import { DEFAULT } from "@constant/user";
import error from "@utils/error";
import logger from "@utils/logger";
import user from "@utils/user";
import Message from "tdesign-miniprogram/message/index";
import Toast from "tdesign-miniprogram/toast/index";
import type {
  ChooseAvatarButtonTap,
  WxGetFileSystemManagerReadFileSuccess,
} from "types/wechat";

Page({
  data: {
    avatar: "",
  },
  async onShow() {
    const u = await user.detail();

    this.setData({ avatar: u.config?.avatar ?? DEFAULT.CONFIG.AVATAR });
  },
  async onChooseAvatar(e: ChooseAvatarButtonTap<unknown, unknown>) {
    try {
      await wx.showLoading({ title: "处理中", icon: "loading", mask: true });

      const res = await wx.compressImage({
        src: e.detail.avatarUrl.toString(),
        quality: 50,
      });

      let localFilePath = res.tempFilePath;
      if (
        localFilePath.startsWith("http://") ||
        localFilePath.startsWith("https://")
      ) {
        const downloadRes: { tempFilePath: string } = await new Promise(
          (resolve, reject) => {
            wx.downloadFile({
              url: localFilePath,
              success: resolve,
              fail: reject,
            });
          },
        );
        localFilePath = downloadRes.tempFilePath;
      }

      const fileRes: WxGetFileSystemManagerReadFileSuccess = await new Promise(
        (resolve, reject) => {
          wx.getFileSystemManager().readFile({
            filePath: localFilePath,
            encoding: "base64",
            success: resolve,
            fail: reject,
          });
        },
      );

      this.setData({
        avatar: `data:image/jpeg;base64,${String(fileRes.data)}`,
      });
    } catch (e: unknown) {
      logger.error("头像处理失败", e);

      Toast({
        message: "头像处理失败，请重试",
        theme: "error",
        duration: 2000,
        direction: "column",
      });
    } finally {
      await wx.hideLoading();
    }
  },
  async submit() {
    Toast({
      message: "更新中...",
      theme: "loading",
      duration: 5000,
      direction: "column",
      preventScrollThrough: true,
    });

    try {
      await api.editAvatar(this.data.avatar);

      // 同步完成之后更新下全局的用户信息状态
      await user.sync();

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
