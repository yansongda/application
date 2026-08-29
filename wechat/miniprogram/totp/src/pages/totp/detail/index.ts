import api from "@api/totp";
import { substr } from "@utils/string";
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
    isLoading: true,
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
    this.setData({ isLoading: true });

    api
      .detail(this.data.id)
      .then((response: Item) => {
        this.response = response;
        this.setData({
          isLoading: false,
          id: response.id,
          issuer: substr(response.issuer),
          username: substr(response.username),
          config: response.config,
        });
      })
      .catch(() => {
        this.setData({ isLoading: false, dialogVisible: true });
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
