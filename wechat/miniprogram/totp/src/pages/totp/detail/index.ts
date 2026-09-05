import { substr } from "@utils/string";
import { readCache, syncFromRemote } from "@utils/totp-cache";
import Toast from "tdesign-miniprogram/toast/index";
import type { CacheItem } from "types/totp";
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
  // gotoEdit 仅依赖 issuer/username 传参，故 response 只需这两个字段。
  response: { issuer: "", username: "" },
  onLoad(query: Query) {
    this.data.id = query.id || "0";
  },
  onShow() {
    Toast({
      message: "加载中...",
      theme: "loading",
      duration: 5000,
      direction: "column",
      preventScrollThrough: true,
    });

    const item = readCache()?.items.find(
      (cacheItem) => cacheItem.id === this.data.id,
    );

    if (typeof item !== "undefined") {
      this.applyItem(item);

      return;
    }

    // 本地缓存未命中（首次使用或缓存异常）：同步远端后重查。
    syncFromRemote()
      .then(() => {
        const fresh = readCache()?.items.find(
          (cacheItem) => cacheItem.id === this.data.id,
        );

        if (typeof fresh === "undefined") {
          this.showLoadError();

          return;
        }

        this.applyItem(fresh);
      })
      .catch(() => {
        this.showLoadError();
      });
  },
  applyItem(item: CacheItem) {
    Toast({
      message: "加载成功",
      theme: "success",
      duration: 100,
      direction: "column",
    });

    this.response = { issuer: item.issuer, username: item.username };

    this.setData({
      id: item.id,
      issuer: substr(item.issuer),
      username: substr(item.username),
      config: { period: item.period },
    });
  },
  showLoadError() {
    Toast({
      message: "加载失败",
      theme: "error",
      duration: 100,
      direction: "column",
    });

    this.setData({ dialogVisible: true });
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
