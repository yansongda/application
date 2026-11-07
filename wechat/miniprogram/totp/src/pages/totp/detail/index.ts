import api from "@api/totp";
import { copyText } from "@utils/clipboard";
import error from "@utils/error";
import { substr } from "@utils/string";
import { computeSnapshot } from "@utils/totp";
import { readCache, syncFromRemote, updateItemFields } from "@utils/totp-cache";
import Message from "tdesign-miniprogram/message/index";
import Toast from "tdesign-miniprogram/toast/index";
import type { CacheItem, EditPinnedRequest } from "types/totp";
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
    code: "",
    remaining: 0,
    progress: 0,
    issuer: "",
    username: "",
    tagDisplay: "未设置",
    pinnedDisplay: "未置顶",
    config: { period: 30, digits: 6, algorithm: "SHA1" },
  },
  // gotoEdit 仅依赖 issuer/username 传参，故 response 只需这两个字段。
  response: { issuer: "", username: "" },
  // 计时所需的密钥/周期等字段不参与渲染，挂在实例上避免 setData 无谓重渲染。
  item: null as CacheItem | null,
  timer: null as number | null,
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
  // 页面隐藏/卸载时停表；onShow 会重新启动（从缓存重读）。
  onHide() {
    this.stopTimer();
  },
  onUnload() {
    this.stopTimer();
  },
  applyItem(item: CacheItem) {
    this.stopTimer();
    this.item = item;
    this.response = { issuer: item.issuer, username: item.username };
    const tags = item.tags ?? [];

    this.setData({
      id: item.id,
      code: "",
      remaining: 0,
      progress: 0,
      issuer: substr(item.issuer),
      username: substr(item.username),
      tagDisplay: tags.length > 0 ? `#${tags[0]}` : "未设置",
      pinnedDisplay: item.pinned === true ? "已置顶" : "未置顶",
      config: {
        period: item.period,
        digits: item.digits ?? 6,
        algorithm: item.algorithm ?? "SHA1",
      },
    });

    // 先立即算一次再起表，避免首秒空白。
    this.tick();
    this.timer = setInterval(() => this.tick(), 1000);
  },
  stopTimer() {
    if (this.timer !== null) {
      clearInterval(this.timer);
      this.timer = null;
    }
  },
  tick() {
    const item = this.item;

    if (item === null) {
      return;
    }

    const snapshot = computeSnapshot(
      item.secret,
      item.period,
      item.digits,
      item.algorithm,
      Date.now(),
    );
    const patch: { code?: string; remaining: number; progress: number } = {
      remaining: snapshot.remaining,
      progress: snapshot.progress,
    };

    // 验证码仅在周期边界变化，code 不变时跳过该字段，减少无谓重渲染。
    if (snapshot.code !== this.data.code) {
      patch.code = snapshot.code;
    }

    this.setData(patch);
  },
  async copyCode() {
    if (this.data.code.length === 0) {
      return;
    }

    const ok = await copyText(this.data.code);

    if (!ok) {
      Toast({
        message: "复制失败",
        theme: "error",
        duration: 1500,
        direction: "column",
      });
    }
  },
  async gotoTag() {
    const tags = this.item?.tags ?? [];

    await wx.navigateTo({
      url: `/pages/totp/tag/index?id=${encodeURIComponent(this.data.id)}&tag=${encodeURIComponent(tags[0] ?? "")}`,
    });
  },
  async togglePinned() {
    const item = this.item;

    if (item === null) {
      return;
    }

    const next = item.pinned !== true;

    try {
      await api.editPinned({
        id: this.data.id,
        pinned: next,
      } as EditPinnedRequest);
      updateItemFields(this.data.id, { pinned: next });
      this.item = { ...item, pinned: next };
      this.setData({ pinnedDisplay: next ? "已置顶" : "未置顶" });
    } catch (e: unknown) {
      Toast({
        message: "操作失败",
        theme: "error",
        duration: 100,
        direction: "column",
      });

      Message.error({
        content: `置顶失败：${error.getErrorMessage(e)}`,
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    }
  },
  gotoHelp() {
    wx.navigateTo({ url: "/pages/help/index" });
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
  showLoadError() {
    Toast({
      message: "加载失败",
      theme: "error",
      duration: 100,
      direction: "column",
    });

    this.setData({ dialogVisible: true });
  },
  dialogConfirm() {
    this.setData({ dialogVisible: false });

    this.onShow();
  },
  dialogCancel() {
    this.setData({ dialogVisible: false });
  },
});
