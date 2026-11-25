import api from "@api/totp";
import { ensureAuthenticated, isAccessTokenFresh } from "@utils/app";
import error from "@utils/error";
import {
  collectTagStats,
  countPinned,
  filterItems,
  groupItems,
  ItemFilterKind,
  ItemGroupKind,
  type ItemView,
  sortPinnedFirst,
  type TagStat,
} from "@utils/item-filter";
import { withLoading } from "@utils/loading";
import logger from "@utils/logger";
import { notify, toast } from "@utils/notify";
import { guardOnShow, guardOnUnlocked } from "@utils/page-guard";
import { hasSettings } from "@utils/security";
import { substr } from "@utils/string";
import { syncTabBarSelected, TAB_BAR_INDEX } from "@utils/tab-bar";
import {
  applySort,
  readCache,
  removeItem,
  syncFromRemote,
  updateItemFields,
  upsertItem,
} from "@utils/totp-cache";
import {
  describeOtpError,
  parseTotpUri,
  rebuildTotpUri,
} from "@utils/totp-uri";
import { refreshUser } from "@utils/user-sync";
import {
  applyFilter,
  applyGrouped,
  clearFilter,
  DEFAULT_VIEW_STATE,
  readViewState,
  saveViewState,
  syncView,
  type ViewFilterKind,
} from "@utils/view-state";
import type {
  CacheItem,
  EditPinnedRequest,
  ItemDeleteEvent,
  ItemDetailEvent,
  ItemMessageEvent,
} from "types/totp";
import type { Tap } from "types/wechat";

// 渲染用分组：在 item-filter 的 ItemGroupView 基础上补充标题与组内条目
interface RenderGroup {
  kind: ItemGroupKind;
  tag: string;
  title: string;
  ids: string[];
  items: RenderItem[];
}

// 列表渲染条目：ItemView 基础上携带算码所需字段（卡片组件直接消费）
interface RenderItem extends ItemView {
  secret: string;
  period: number;
  digits?: number;
  algorithm?: string;
}

interface ItemPinEvent {
  detail: {
    id: string;
    pinned: boolean;
  };
}

interface FilterDataset {
  kind: string;
  tag?: string;
}

interface GroupedDataset {
  grouped: boolean;
}

// 视图状态与筛选/分组互斥语义（全部 + 平铺）对齐华为 ListViewState
const ROW_HEIGHT = 100;

Page({
  data: {
    locked: false,
    items: [] as CacheItem[],
    groups: [] as RenderGroup[],
    visibleItems: [] as RenderItem[],
    query: "",
    filterKind: "all" as ViewFilterKind,
    filterTag: "",
    grouped: false,
    filterLabel: "筛选",
    viewActive: false,
    menuVisible: false,
    menuStats: {
      total: 0,
      pinned: 0,
      tags: [] as TagStat[],
    },
    totalCount: 0,
    pinnedCount: 0,
    isError: false,
    isCreating: false,
    dialogVisible: false,
    currentItemId: "0",
    isSortMode: false,
    dragItems: [] as (CacheItem & { y: number; translateY: number })[],
    draggingIndex: -1,
    isDragging: false,
    touchStartY: 0,
    isRefreshing: false,
  },
  // 视图状态（筛选/分组）：页面级属性，不参与 setData
  viewState: { ...DEFAULT_VIEW_STATE },
  snapshotIds: [] as string[],
  // 写接口防重入：loading 期间忽略重复点击
  pinning: false,
  deleting: false,
  // 首屏标记：首次 onShow 显示 loading，之后（切 tab / 从子页返回）静默同步
  firstLoad: true,
  async onShow() {
    // 自定义 tabBar 不会自动高亮：切回本页时把选中态指回 TOTP
    syncTabBarSelected(this, TAB_BAR_INDEX.totp);

    // 应用锁守卫：锁定时不发请求、不启动计时，直接渲染遮罩
    if (guardOnShow(this)) {
      return;
    }

    if (this.data.isCreating) {
      return;
    }
    this.setData({ isError: false });

    try {
      if (isAccessTokenFresh()) {
        // token 仍新鲜：ensureAuthenticated 直接返回，不产生请求，因此不出 loading
        await ensureAuthenticated();
      } else {
        await withLoading("登录中...", () => ensureAuthenticated());
      }
    } catch {
      toast.error("登录失败", 100);

      this.setData({ isError: true });

      return;
    }

    // 新装/重装：本地安全设置已被清空，须先从服务端恢复应用锁再拉取验证码，
    // 否则首屏漏锁、直到下一个页面才要求验证（完全删除后重新扫码可复现）
    if (!hasSettings()) {
      await refreshUser();

      if (guardOnShow(this)) {
        return;
      }
    }

    // 首屏出 loading，切 tab / 从子页返回时静默同步（避免每次 onShow 都闪一下 loading）
    await this.loadItems({ silent: !this.firstLoad });
    this.firstLoad = false;

    // 冷启动恢复筛选/分组视图，并在数据刷新后清理失效状态
    this.viewState = readViewState();
    this.recompute();
  },
  // 解锁成功：解除锁定并重新执行 onShow（恢复取数与计时）
  onUnlocked() {
    guardOnUnlocked(this);
    this.onShow();
  },
  retry() {
    // 重试需要 loading 反馈，重置首屏标记后重跑 onShow
    this.firstLoad = true;
    this.onShow();
  },
  loadItems(options: { silent?: boolean } = {}): Promise<void> {
    const cache = readCache();

    // 优先用本地缓存渲染，避免等待网络时验证码区域空白。
    if (cache !== null) {
      this.renderItems(cache.items);
    }

    const sync = (): ReturnType<typeof syncFromRemote> => syncFromRemote();
    const request = options.silent ? sync() : withLoading("加载中...", sync);

    return request
      .then((fresh) => {
        this.renderItems(fresh.items);
        this.recompute();
      })
      .catch((e: unknown) => {
        if (cache === null) {
          // 无本地缓存兜底：显示错误态与重试按钮
          this.setData({ isError: true });

          notify.error(this, `加载失败：${error.getErrorMessage(e)}`);
        } else {
          // 已有本地缓存兜底：保持缓存渲染，静默降级。
          logger.warning("同步 TOTP 列表失败，已使用本地缓存渲染", e);
        }

        this.recompute();
      });
  },
  renderItems(items: CacheItem[]) {
    this.setData({
      items: items.map((item) => ({
        ...item,
        issuer: substr(item.issuer, 7),
        username: substr(item.username, 50),
      })),
      totalCount: items.length,
    });
  },
  // 列表唯一渲染入口：缓存 → ItemView → 过滤 → 置顶优先 → 分组；
  // 同时清理失效的视图状态（标签被删/置顶清零时回退「全部」）
  recompute() {
    const cache = readCache();
    const rawItems = cache?.items ?? [];

    const views: RenderItem[] = rawItems.map((item) => ({
      id: item.id,
      issuer: substr(item.issuer, 7),
      username: substr(item.username, 50),
      tags: item.tags ?? [],
      pinned: item.pinned === true,
      secret: item.secret,
      period: item.period,
      digits: item.digits,
      algorithm: item.algorithm,
    }));

    const synced = syncView(this.viewState, views);

    if (synced.changed) {
      this.viewState = synced.state;
      saveViewState(this.viewState);
    }

    const kind: ItemFilterKind =
      this.viewState.kind === "pinned"
        ? ItemFilterKind.PINNED
        : this.viewState.kind === "tag"
          ? ItemFilterKind.TAG
          : ItemFilterKind.ALL;
    const filtered = filterItems(
      views,
      kind,
      this.viewState.tag,
      this.data.query,
    );
    const ordered = this.data.isSortMode ? filtered : sortPinnedFirst(filtered);
    const grouped = this.viewState.grouped && !this.data.isSortMode;
    const byId = new Map<string, RenderItem>(
      ordered.map((view) => [view.id, view as RenderItem]),
    );
    const groups: RenderGroup[] = grouped
      ? groupItems(ordered).map((group) => ({
          kind: group.kind,
          tag: group.tag,
          title:
            group.kind === ItemGroupKind.PINNED
              ? "置顶"
              : group.kind === ItemGroupKind.UNASSIGNED
                ? "未分类"
                : group.tag,
          ids: group.ids,
          items: group.ids.flatMap((id) => {
            const view = byId.get(id);

            return typeof view === "undefined" ? [] : [view];
          }),
        }))
      : [];
    const visibleItems: RenderItem[] = grouped ? [] : (ordered as RenderItem[]);
    const pinnedCount = countPinned(views);
    let filterLabel = "筛选";

    if (this.viewState.grouped) {
      filterLabel = "分组";
    } else if (this.viewState.kind === "pinned") {
      filterLabel = "置顶";
    } else if (this.viewState.kind === "tag" && this.viewState.tag.length > 0) {
      filterLabel = `#${this.viewState.tag}`;
    }

    this.setData({
      items: rawItems.map((item) => ({
        ...item,
        issuer: substr(item.issuer, 7),
        username: substr(item.username, 50),
      })),
      totalCount: rawItems.length,
      pinnedCount,
      menuStats: {
        total: views.length,
        pinned: pinnedCount,
        tags: collectTagStats(views),
      },
      groups,
      visibleItems,
      filterKind: this.viewState.kind,
      filterTag: this.viewState.tag,
      grouped,
      filterLabel,
      viewActive: this.viewState.grouped || this.viewState.kind !== "all",
    });
  },
  onQueryInput(e: WechatMiniprogram.Input) {
    this.setData({ query: e.detail.value });
    this.recompute();
  },
  openFilterMenu() {
    this.setData({ menuVisible: true });
  },
  onMenuVisibleChange(e: { detail: { visible: boolean } }) {
    if (!e.detail.visible) {
      this.setData({ menuVisible: false });
    }
  },
  onFilterTap(e: Tap<FilterDataset, FilterDataset>) {
    const kind = e.currentTarget.dataset.kind as ViewFilterKind;

    if (kind !== "all" && kind !== "pinned" && kind !== "tag") {
      return;
    }

    if (kind === "pinned" && this.data.menuStats.pinned === 0) {
      return;
    }

    this.viewState = applyFilter(
      this.viewState,
      kind,
      e.currentTarget.dataset.tag ?? "",
    );
    saveViewState(this.viewState);
    this.setData({ menuVisible: false });
    this.recompute();
  },
  onGroupedTap(e: Tap<GroupedDataset, GroupedDataset>) {
    this.viewState = applyGrouped(
      this.viewState,
      e.currentTarget.dataset.grouped === true,
    );
    saveViewState(this.viewState);
    this.setData({ menuVisible: false });
    this.recompute();
  },
  clearFilter() {
    this.viewState = clearFilter(this.viewState);
    saveViewState(this.viewState);
    this.recompute();
  },
  goCreate() {
    wx.navigateTo({ url: "/pages/totp/create/index" });
  },
  goHelp() {
    wx.navigateTo({ url: "/pages/help/index" });
  },
  onImport() {
    wx.navigateTo({ url: "/pages/backup/index?mode=import" });
  },
  onFabClick() {
    wx.showActionSheet({
      itemList: ["扫码添加", "手动输入"],
      success: (res) => {
        if (res.tapIndex === 0) {
          this.addByScan();
        } else {
          this.goCreate();
        }
      },
    });
  },
  async addByScan() {
    this.setData({ isCreating: true });

    let result: WechatMiniprogram.ScanCodeSuccessCallbackResult;

    try {
      result = await wx.scanCode({ scanType: ["qrCode"] });
    } catch {
      // 用户取消：静默返回
      this.setData({ isCreating: false });

      return;
    }

    let uri = "";

    // strict 解析 + 重建：非规范 Base32 / 非法 otpauth 链接在本地拦截
    try {
      const parsed = parseTotpUri(result.result);
      uri = rebuildTotpUri(parsed);
    } catch (e: unknown) {
      this.setData({ isCreating: false });

      notify.error(this, describeOtpError(e));

      return;
    }

    try {
      const item = await withLoading("创建中...", () => api.create(uri));

      // 直接用 create 响应（即服务端入库值）乐观写入缓存，
      // 避免前端二次解析 URI 与后端 from_url_unchecked 的语义差异。
      upsertItem({
        id: item.id,
        issuer: item.issuer,
        username: item.username,
        secret: item.config.secret,
        period: item.config.period,
        digits: item.config.digits,
        algorithm: item.config.algorithm,
      });

      toast.success("添加成功", 100);

      this.loadItems();
    } catch (e: unknown) {
      notify.error(this, `添加失败：${error.getErrorMessage(e)}`);
    } finally {
      this.setData({ isCreating: false });
    }
  },
  async togglePin(e: ItemPinEvent) {
    if (this.pinning) {
      return;
    }

    const { id, pinned } = e.detail;

    this.pinning = true;

    try {
      await withLoading("处理中...", () =>
        api.editPinned({ id, pinned } as EditPinnedRequest),
      );
      updateItemFields(id, { pinned });

      toast.success(pinned ? "已置顶" : "已取消置顶", 100);

      this.recompute();
    } catch (err: unknown) {
      notify.error(this, `置顶失败：${error.getErrorMessage(err)}`);
    } finally {
      this.pinning = false;
    }
  },
  async itemDetail(e: ItemDetailEvent) {
    const id = e.detail;

    await wx.navigateTo({
      url: `/pages/totp/detail/index?id=${encodeURIComponent(id)}`,
    });
  },
  itemDelete(e: ItemDeleteEvent) {
    // 删除请求进行中不响应新的删除入口，避免 currentItemId 被覆盖
    if (this.deleting) {
      return;
    }

    const currentItemId = e.detail;

    this.setData({ dialogVisible: true, currentItemId });
  },
  itemMessage(e: ItemMessageEvent) {
    notify.error(this, e.detail);
  },
  async dialogConfirm() {
    if (this.deleting) {
      return;
    }

    const id = this.data.currentItemId;

    this.deleting = true;
    // 先关闭确认弹框（弹框 zIndex 高于 Toast 遮罩层），再出「处理中」提示
    this.setData({ dialogVisible: false });

    try {
      await withLoading("处理中...", () => api.deleteTotp(id));
      removeItem(id);
      this.recompute();
    } catch (e: unknown) {
      notify.error(this, `删除失败：${error.getErrorMessage(e)}`);
    } finally {
      this.deleting = false;
      this.setData({ currentItemId: "0" });
    }
  },
  dialogCancel() {
    // 删除请求进行中不允许关弹框（弹框此时已关闭），避免语义歧义
    if (this.deleting) {
      return;
    }

    this.setData({ dialogVisible: false, currentItemId: "0" });
  },
  // ---- 拖拽排序（沿用现有实现：100px 行高、350ms 长按、y/translateY 拖拽）----
  enterSortMode() {
    // 排序作用于完整列表：清空搜索/筛选/分组，落盘「全部 + 平铺」
    this.viewState = applyFilter(this.viewState, "all", "");
    saveViewState(this.viewState);
    this.snapshotIds = this.data.items.map((item) => item.id);

    this.setData({
      isSortMode: true,
      query: "",
      filterKind: "all",
      filterTag: "",
      grouped: false,
      dragItems: this.data.items.map((item, index) => ({
        ...item,
        y: index * ROW_HEIGHT,
        translateY: 0,
      })),
    });

    this.recompute();
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
    let newIndex = Math.round(finalY / ROW_HEIGHT);
    newIndex = Math.max(0, Math.min(this.data.dragItems.length - 1, newIndex));

    if (newIndex !== index) {
      const newDragItems = [...this.data.dragItems];
      const [movedItem] = newDragItems.splice(index, 1);
      newDragItems.splice(newIndex, 0, movedItem);

      newDragItems.forEach((item, i) => {
        item.y = i * ROW_HEIGHT;
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
  async saveSort() {
    const reorderedItems = this.data.dragItems.map((di) => {
      const { y: _y, translateY: _t, ...rest } = di;
      return rest as CacheItem;
    });
    const sortItems = reorderedItems.map((item, index) => ({
      id: item.id,
      sort: reorderedItems.length - 1 - index,
    }));

    try {
      await withLoading("保存中...", () => api.sort(sortItems));
      // 服务端成功后才覆盖缓存顺序
      applySort(reorderedItems.map((item) => item.id));
      this.snapshotIds = [];

      this.setData({
        isSortMode: false,
        dragItems: [],
        draggingIndex: -1,
        isDragging: false,
      });

      this.recompute();
    } catch (e: unknown) {
      // 服务端未变更：按进入排序时的 id 快照恢复缓存顺序渲染
      const cache = readCache();
      const byId = new Map((cache?.items ?? []).map((item) => [item.id, item]));
      const restored: CacheItem[] = this.snapshotIds.flatMap((id) => {
        const item = byId.get(id);

        return typeof item === "undefined" ? [] : [item];
      });
      this.snapshotIds = [];

      this.setData({
        isSortMode: false,
        dragItems: [],
        draggingIndex: -1,
        isDragging: false,
      });

      if (restored.length > 0) {
        this.renderItems(restored);
      }

      this.recompute();

      notify.error(this, `排序失败：${error.getErrorMessage(e)}`);
    }
  },
  onPullDownRefresh() {
    if (this.data.isRefreshing) {
      wx.stopPullDownRefresh();

      return;
    }

    this.setData({ isRefreshing: true });

    this.loadItems().finally(() => {
      this.setData({ isRefreshing: false });
      wx.stopPullDownRefresh();
    });
  },
});
