import api from "@api/totp";
import { substr } from "@utils/string";
import Toast from "tdesign-miniprogram/toast/index";
import type { Item } from "types/totp";
import type { Tap } from "types/wechat";

interface Query {
  id?: string;
}

interface Dataset {
  type: string;
}

Page({
  data: {
    dialogVisible: false,
    id: "0",
    issuer: "",
    username: "",
    config: { period: 30 },
  },
  response: {} as Item,
  onLoad(query: Query) {
    this.data.id = query.id || "0";
  },
  onShow() {
    Toast({
      message: "加载中...",
      theme: "loading",
      duration: 5000,
      direction: "column",
    });

    api
      .detail(this.data.id)
      .then((response: Item) => {
        Toast({
          message: "加载成功",
          theme: "success",
          duration: 100,
          direction: "column",
        });

        this.response = response;
        this.setData({
          id: response.id,
          issuer: substr(response.issuer),
          username: substr(response.username),
          config: response.config,
        });
      })
      .catch(() => {
        Toast({
          message: "加载失败",
          theme: "error",
          duration: 100,
          direction: "column",
        });

        this.setData({ dialogVisible: true });
      });
  },
  async gotoEdit(e: Tap<Dataset, Dataset>) {
    let url = "";

    switch (e.currentTarget.dataset.type) {
      case "issuer":
        url = `/pages/totp/edit/issuer?id=${this.data.id}&issuer=${encodeURIComponent(this.response.issuer)}`;
        break;
      case "username":
        url = `/pages/totp/edit/username?id=${this.data.id}&username=${encodeURIComponent(this.response.username)}`;
        break;
      default:
        break;
    }

    if (url.length > 0) {
      await wx.navigateTo({ url });
    }
  },
  dialogConfirm() {
    this.setData({ dialogVisible: false });

    this.onShow();
  },
  dialogCancel() {
    this.setData({ dialogVisible: false });
  },
});
