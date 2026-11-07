import api from "@api/totp";
import { syncOnPageShow as appLockSyncOnPageShow } from "@utils/app-lock";
import error from "@utils/error";
import { collectTags, type ItemView } from "@utils/item-filter";
import { readCache, updateItemFields } from "@utils/totp-cache";
import Message from "tdesign-miniprogram/message/index";
import Toast from "tdesign-miniprogram/toast/index";
import type { EditTagsRequest } from "types/totp";

interface Query {
  id?: string;
  tag?: string;
}

interface ChangeEvent {
  detail: {
    value: string;
  };
}

interface ChipTap {
  currentTarget: {
    dataset: {
      tag: string;
    };
  };
}

// 预设标签与华为端一致；输入上限 12（后端单标签上限 32）
const PRESET_TAGS = ["工作", "个人", "财务", "开发", "其他"];

Page({
  data: {
    locked: false,
    id: "0",
    tag: "",
    chips: [] as string[],
  },
  saving: false,
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
    const tag = query.tag ? decodeURIComponent(query.tag) : "";
    const cacheItems = readCache()?.items ?? [];
    const suggestions = collectTags(
      cacheItems.map((item) => {
        const view: ItemView = {
          id: item.id,
          issuer: item.issuer,
          username: item.username,
          tags: item.tags ?? [],
          pinned: item.pinned === true,
        };

        return view;
      }),
    );
    // 建议标签：已存在于预设或当前已选中（输入框中）的不再重复展示
    const chips = [
      ...PRESET_TAGS,
      ...suggestions.filter(
        (suggestion) => !PRESET_TAGS.includes(suggestion) && suggestion !== tag,
      ),
    ];

    this.setData({ id: query.id || "0", tag, chips });
  },
  onTagChange(e: ChangeEvent) {
    this.setData({ tag: e.detail.value });
  },
  selectChip(e: ChipTap) {
    this.setData({ tag: e.currentTarget.dataset.tag });
  },
  async save() {
    if (this.saving) {
      return;
    }

    const tag = this.data.tag.trim();
    const tags = tag.length > 0 ? [tag] : [];

    this.saving = true;

    Toast({
      message: "保存中...",
      theme: "loading",
      duration: 5000,
      direction: "column",
      preventScrollThrough: true,
    });

    try {
      await api.editTags({ id: this.data.id, tags } as EditTagsRequest);
      updateItemFields(this.data.id, { tags });

      Toast({
        message: "保存成功",
        theme: "success",
        duration: 1500,
        direction: "column",
        preventScrollThrough: true,
      });

      setTimeout(() => wx.navigateBack(), 1500);
    } catch (err: unknown) {
      this.saving = false;

      Toast({
        message: "保存失败",
        theme: "error",
        duration: 100,
        direction: "column",
      });

      Message.error({
        content: `保存失败：${error.getErrorMessage(err)}`,
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    }
  },
  async cancel() {
    await wx.navigateBack();
  },
});
