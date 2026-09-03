import api from "@api/user";
import { DEFAULT } from "@constant/user";
import error from "@utils/error";
import user from "@utils/user";
import Message from "tdesign-miniprogram/message/index";
import Toast from "tdesign-miniprogram/toast/index";
import type { FormSubmit } from "types/wechat";

interface FormData {
  nickname: string;
}

Page({
  data: {
    nickname: "",
  },
  async onShow() {
    const u = await user.detail();

    this.setData({ nickname: u.config?.nickname ?? DEFAULT.CONFIG.NICKNAME });
  },
  async submit(e: FormSubmit<FormData>) {
    Toast({
      message: "更新中...",
      theme: "loading",
      duration: 5000,
      direction: "column",
      preventScrollThrough: true,
    });

    try {
      await api.editNickname(e.detail.value.nickname);

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
