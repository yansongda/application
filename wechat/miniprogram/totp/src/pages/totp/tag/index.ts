import api from "@api/totp";
import error from "@utils/error";
import { collectTags, type ItemView } from "@utils/item-filter";
import { withLoading } from "@utils/loading";
import { notify, toast } from "@utils/notify";
import { guardOnShow, guardOnUnlocked } from "@utils/page-guard";
import { readCache, updateItemFields } from "@utils/totp-cache";
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
    guardOnShow(this);
  },
  // 解锁成功：页面无取数/计时，仅解除锁定
  onUnlocked() {
    guardOnUnlocked(this);
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

    try {
      await withLoading("保存中...", () =>
        api.editTags({ id: this.data.id, tags } as EditTagsRequest),
      );
      updateItemFields(this.data.id, { tags });

      toast.success("保存成功", 1500);

      setTimeout(() => wx.navigateBack(), 1500);
    } catch (err: unknown) {
      this.saving = false;

      notify.error(this, `保存失败：${error.getErrorMessage(err)}`);
    }
  },
  async cancel() {
    await wx.navigateBack();
  },
});
