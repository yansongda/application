import api from "@api/totp";
import { syncOnPageShow as appLockSyncOnPageShow } from "@utils/app-lock";
import { copyText } from "@utils/clipboard";
import error from "@utils/error";
import { withLoading } from "@utils/loading";
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

interface Snapshot {
  code: string;
  remaining: number;
  progressPercent: number;
}

Page({
  data: {
    locked: false,
    dialogVisible: false,
    id: "0",
    code: "",
    remaining: 0,
    progressPercent: 0,
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
  pinning: false,
  onLoad(query: Query) {
    this.data.id = query.id || "0";
  },
  onShow() {
    // 应用锁守卫：锁定时不发请求、不启动计时，直接渲染遮罩
    const locked = appLockSyncOnPageShow();

    if (locked !== this.data.locked) {
      this.setData({ locked });
    }

    if (locked) {
      return;
    }

    const item = readCache()?.items.find(
      (cacheItem) => cacheItem.id === this.data.id,
    );

    if (typeof item !== "undefined") {
      // 列表页展示前已同步远端，缓存即最新：直接渲染，不发请求也不出 loading
      this.applyItem(item);

      return;
    }

    // 本地缓存未命中（首次使用或缓存异常）：同步远端后重查
    this.loadFromRemote();
  },
  // 解锁成功：重新执行 onShow（重读缓存并重启计时）
  onUnlocked() {
    this.setData({ locked: false });
    this.onShow();
  },
  // 页面隐藏/卸载时停表；onShow 会重新启动（从缓存重读）。
  onHide() {
    this.stopTimer();
  },
  onUnload() {
    this.stopTimer();
  },
  // 仅在缓存未命中、确实要发请求时出 loading；命中缓存路径不会走到这里
  async loadFromRemote() {
    try {
      await withLoading("加载中...", () => syncFromRemote());

      const fresh = readCache()?.items.find(
        (cacheItem) => cacheItem.id === this.data.id,
      );

      if (typeof fresh === "undefined") {
        this.showLoadError();

        return;
      }

      this.applyItem(fresh);
    } catch {
      this.showLoadError();
    }
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
      progressPercent: 0,
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
    this.scheduleTick();
  },
  // 一次算出验证码、剩余秒数与进度条百分比
  computeCurrentSnapshot(): Snapshot | null {
    const item = this.item;

    if (item === null) {
      return null;
    }

    const snapshot = computeSnapshot(
      item.secret,
      item.period,
      item.digits,
      item.algorithm,
      Date.now(),
    );

    return {
      code: snapshot.code,
      remaining: snapshot.remaining,
      // 进度条按剩余时间收缩（与列表卡片 remainSeconds / period 同语义），
      // 不用 otp 库 progress() 的「已走过比例」，否则方向相反
      progressPercent: (snapshot.remaining / item.period) * 100,
    };
  },
  scheduleTick() {
    this.stopTimer();

    // 对齐整秒边界刷新（与列表卡片同策略），避免验证码在周期边界最多滞后 1 秒
    const delay = 1000 - (Date.now() % 1000);

    this.timer = setTimeout(() => {
      this.tick();
      this.scheduleTick();
    }, delay);
  },
  stopTimer() {
    if (this.timer !== null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  },
  tick() {
    const current = this.computeCurrentSnapshot();

    if (current === null) {
      return;
    }

    const patch: {
      code?: string;
      remaining: number;
      progressPercent: number;
    } = {
      remaining: current.remaining,
      progressPercent: current.progressPercent,
    };

    // 验证码仅在周期边界变化，code 不变时跳过该字段，减少无谓重渲染。
    if (current.code !== this.data.code) {
      patch.code = current.code;
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

    if (item === null || this.pinning) {
      return;
    }

    const next = item.pinned !== true;

    this.pinning = true;

    try {
      await withLoading("处理中...", () =>
        api.editPinned({
          id: this.data.id,
          pinned: next,
        } as EditPinnedRequest),
      );
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
    } finally {
      this.pinning = false;
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
