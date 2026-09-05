import api from "@api/totp";
import { CODE } from "@constant/error";
import type { HttpError } from "@models/error";
import { WeixinError } from "@models/error";
import { ensureAuthenticated } from "@utils/app";
import error from "@utils/error";
import logger from "@utils/logger";
import { substr } from "@utils/string";
import { parseUri } from "@utils/totp";
import {
  applySort,
  readCache,
  removeItem,
  syncFromRemote,
  upsertItem,
} from "@utils/totp-cache";
import Message from "tdesign-miniprogram/message/index";
import Toast, { hideToast } from "tdesign-miniprogram/toast/index";
import type {
  CacheItem,
  ItemDeleteEvent,
  ItemDetailEvent,
  ItemMessageEvent,
} from "types/totp";

Page({
  data: {
    isError: false,
    dialogVisible: false,
    currentItemId: "0",
    items: [] as CacheItem[],
    isSortMode: false,
    dragItems: [] as (CacheItem & { y: number; translateY: number })[],
    draggingIndex: -1,
    isDragging: false,
    touchStartY: 0,
  },
  isCreating: false,
  async onShow() {
    if (this.isCreating) {
      return;
    }
    this.setData({ isError: false });

    Toast({
      message: "登录中...",
      theme: "loading",
      duration: 5000,
      direction: "column",
      preventScrollThrough: true,
    });

    try {
      await ensureAuthenticated();
      this.loadItems();
    } catch {
      Toast({
        message: "登录失败",
        theme: "error",
        duration: 100,
        direction: "column",
      });

      this.setData({ isError: true });
    }
  },
  retry() {
    this.onShow();
  },
  loadItems() {
    const cache = readCache();

    // 优先用本地缓存渲染，避免等待网络时验证码区域空白。
    if (cache !== null) {
      this.renderItems(cache.items);
    }

    Toast({
      message: "加载中...",
      theme: "loading",
      duration: 5000,
      direction: "column",
      preventScrollThrough: true,
    });

    syncFromRemote()
      .then((fresh) => {
        Toast({
          message: "加载成功",
          theme: "success",
          duration: 100,
          direction: "column",
        });

        this.renderItems(fresh.items);
      })
      .catch((e: unknown) => {
        if (cache !== null) {
          // 已有本地缓存兜底：保持缓存渲染，静默降级。
          logger.warning("同步 TOTP 列表失败，已使用本地缓存渲染", e);
          hideToast();

          return;
        }

        this.setData({ isError: true });

        Toast({
          message: "加载失败",
          theme: "error",
          duration: 100,
          direction: "column",
        });

        Message.error({
          content: `加载失败：${error.getErrorMessage(e)}`,
          duration: 5000,
          offset: [20, 32],
          context: this,
        });
      });
  },
  renderItems(items: CacheItem[]) {
    this.setData({
      items: items.map((item) => ({
        ...item,
        issuer: substr(item.issuer, 7),
        username: substr(item.username, 50),
      })),
    });
  },
  async create() {
    this.isCreating = true;

    const scan = await wx.scanCode({ scanType: ["qrCode"] }).catch(() => {
      this.isCreating = false;
      throw new WeixinError(CODE.WEIXIN_QR_CODE);
    });

    api
      .create(scan.result)
      .then((item) => {
        const parsed = parseUri(scan.result);

        upsertItem({
          id: item.id,
          issuer: parsed.issuer || "未知发行方",
          username: parsed.username,
          secret: parsed.secret,
          period: parsed.period,
        });
      })
      .catch((e: HttpError) =>
        Message.error({
          content: e.message,
          duration: 5000,
          offset: [20, 32],
          context: this,
        }),
      )
      .finally(() => {
        this.isCreating = false;
        this.loadItems();
      });
  },
  async itemDetail(e: ItemDetailEvent) {
    const id = e.detail;

    await wx.navigateTo({
      url: `/pages/totp/detail/index?id=${encodeURIComponent(id)}`,
    });
  },
  itemDelete(e: ItemDeleteEvent) {
    const currentItemId = e.detail;

    this.setData({ dialogVisible: true, currentItemId });
  },
  itemMessage(e: ItemMessageEvent) {
    Message.error({
      content: e.detail,
      duration: 5000,
      offset: [20, 32],
      context: this,
    });
  },
  dialogConfirm() {
    api
      .deleteTotp(this.data.currentItemId)
      .then(() => {
        removeItem(this.data.currentItemId);
      })
      .catch((e: HttpError) =>
        Message.error({
          content: `删除失败：${e.message}`,
          duration: 5000,
          offset: [20, 32],
          context: this,
        }),
      )
      .finally(() => {
        this.dialogCancel();
        this.loadItems();
      });
  },
  dialogCancel() {
    this.setData({ dialogVisible: false, currentItemId: "0" });
  },
  enterSortMode() {
    this.setData({
      isSortMode: true,
      dragItems: this.data.items.map((item, index) => ({
        ...item,
        y: index * 100,
        translateY: 0,
      })),
    });
  },
  exitSortMode() {
    this.setData({ isSortMode: false });
  },
  onTouchStart(e: WechatMiniprogram.TouchEvent) {
    const index = Number(e.currentTarget.dataset.index);
    const touch = e.touches[0];

    this.setData({
      draggingIndex: index,
      touchStartY: touch.clientY,
    });

    setTimeout(() => {
      if (this.data.draggingIndex === index) {
        this.setData({ isDragging: true });
      }
    }, 350);
  },
  onTouchMove(e: WechatMiniprogram.TouchEvent) {
    const touch = e.touches[0];
    const deltaY = touch.clientY - this.data.touchStartY;

    if (!this.data.isDragging) {
      if (Math.abs(deltaY) > 10) {
        this.setData({ draggingIndex: -1 });
      }
      return;
    }

    const newDragItems = [...this.data.dragItems];
    newDragItems[this.data.draggingIndex].translateY = deltaY;
    this.setData({ dragItems: newDragItems });
  },
  onTouchEnd(_e: WechatMiniprogram.TouchEvent) {
    if (!this.data.isDragging) {
      this.setData({ draggingIndex: -1 });
      return;
    }

    const index = this.data.draggingIndex;
    const item = this.data.dragItems[index];
    const finalY = item.y + item.translateY;
    let newIndex = Math.round(finalY / 100);
    newIndex = Math.max(0, Math.min(this.data.dragItems.length - 1, newIndex));

    if (newIndex !== index) {
      const newDragItems = [...this.data.dragItems];
      const [movedItem] = newDragItems.splice(index, 1);
      newDragItems.splice(newIndex, 0, movedItem);

      newDragItems.forEach((item, i) => {
        item.y = i * 100;
        item.translateY = 0;
      });

      this.setData({ dragItems: newDragItems });
    } else {
      const newDragItems = [...this.data.dragItems];
      newDragItems[index].translateY = 0;
      this.setData({ dragItems: newDragItems });
    }

    this.setData({ draggingIndex: -1, isDragging: false });
  },
  saveSort() {
    const reorderedItems = this.data.dragItems.map((di) => {
      const { y: _y, translateY: _t, ...rest } = di;
      return rest as CacheItem;
    });
    this.exitSortMode();
    this.onSortChange({ detail: reorderedItems });
  },

  onSortChange(e: { detail: CacheItem[] }) {
    const originalItems = this.data.items.slice();
    const reorderedItems = e.detail;
    const sortItems = reorderedItems.map((item, index) => ({
      id: item.id,
      sort: reorderedItems.length - 1 - index,
    }));

    api
      .sort(sortItems)
      .then(() => {
        applySort(reorderedItems.map((item) => item.id));
        this.setData({ items: reorderedItems });
      })
      .catch((err: HttpError) => {
        this.setData({ items: originalItems });
        Message.error({
          content: `排序失败：${err.message}`,
          duration: 5000,
          offset: [20, 32],
          context: this,
        });
      });
  },
});
