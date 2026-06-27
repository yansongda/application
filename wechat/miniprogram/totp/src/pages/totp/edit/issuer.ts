import api from "@api/totp";
import error from "@utils/error";
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
    id: "0",
    issuer: "",
  },
  onLoad(query: Query) {
    this.setData({
      id: query.id || "0",
      issuer: query.issuer || "",
    });
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
      await api.editIssuer({
        id: this.data.id,
        issuer: e.detail.value.issuer,
      } as EditIssuerRequest);

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
