import api from "@api/totp";
import { ensureAuthenticated, isAccessTokenFresh } from "@utils/app";
import error from "@utils/error";
import { sortPinnedFirst } from "@utils/item-filter";
import { withLoading } from "@utils/loading";
import logger from "@utils/logger";
import { notify, toast } from "@utils/notify";
import { guardOnShow, guardOnUnlocked } from "@utils/page-guard";
import { hasSettings } from "@utils/security";
import { dropIndex, moveItem } from "@utils/sort-order";
import { syncTabBarSelected, TAB_BAR_INDEX } from "@utils/tab-bar";
import {
  applySort,
  readCache,
  removeItem,
  syncFromRemote,
  toCacheItem,
  updateItemFields,
  upsertItem,
} from "@utils/totp-cache";
import {
  describeOtpError,
  parseTotpUri,
  rebuildTotpUri,
} from "@utils/totp-uri";
import {
  buildListView,
  type ListGroupView,
  type ListItemView,
  type ListMenuStats,
  toListItem,
} from "@utils/totp-view";
import { refreshUser } from "@utils/user-sync";
import {
  applyFilter,
  applyGrouped,
  clearFilter,
  DEFAULT_VIEW_STATE,
  readViewState,
  saveViewState,
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

// 排序模式下的行：卡片条目 + 拖动位移（行高与落位计算见 utils/sort-order.ts）
interface DragRow extends ListItemView {
  translateY: number;
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

// 长按进入拖动（毫秒）与「滚动而非拖动」的位移阈值（px）
const LONG_PRESS_MS = 350;
const MOVE_CANCEL_PX = 10;

Page({
  data: {
    locked: false,
    groups: [] as ListGroupView[],
    visibleItems: [] as ListItemView[],
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
      tags: [] as ListMenuStats["tags"],
    },
    totalCount: 0,
    pinnedCount: 0,
    isError: false,
    isCreating: false,
    dialogVisible: false,
    currentItemId: "0",
    isSortMode: false,
    dragItems: [] as DragRow[],
    draggingIndex: -1,
    isDragging: false,
    touchStartY: 0,
    isRefreshing: false,
  },
  // 视图状态（筛选/分组）：页面级属性，不参与 setData
  viewState: { ...DEFAULT_VIEW_STATE },
  // 长按拖动计时器：松手 / 取消 / 卸载都要清，否则会在已结束的手势上置 isDragging
  pressTimer: null as number | null,
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
      this.recompute(cache.items);
    }

    const sync = (): ReturnType<typeof syncFromRemote> => syncFromRemote();
    const request = options.silent ? sync() : withLoading("加载中...", sync);

    return request
      .then((fresh) => {
        this.recompute(fresh.items);
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
  // 列表唯一渲染入口：派生逻辑全在 utils/totp-view.ts（纯函数、可单测），
  // 这里只负责「取哪个数据源 + 回写失效的视图状态 + setData」。
  // items 入参用于复用调用方刚拿到的缓存，省掉一次 storage 反序列化。
  recompute(items?: CacheItem[]) {
    const rawItems = items ?? readCache()?.items ?? [];
    const built = buildListView({
      items: rawItems,
      viewState: this.viewState,
      query: this.data.query,
      isSortMode: this.data.isSortMode,
    });

    this.viewState = built.viewState;

    if (built.viewStateChanged) {
      saveViewState(this.viewState);
    }

    this.setData(built.model);
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

    this.viewState = applyFilter(kind, e.currentTarget.dataset.tag ?? "");
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
      upsertItem(toCacheItem(item));

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
  // ---- 拖拽排序（100px 行高、350ms 长按；位移只走 setData 路径，避免每次 touchmove 全量序列化）----
  enterSortMode() {
    // 排序作用于完整列表：清空搜索/筛选/分组，落盘「全部 + 平铺」
    this.viewState = applyFilter("all", "");
    saveViewState(this.viewState);

    // 起始顺序沿用当前展示序（置顶优先），避免进入排序模式的瞬间列表跳变
    const rows: DragRow[] = sortPinnedFirst(
      (readCache()?.items ?? []).map(toListItem),
    ).map((row) => ({ ...row, translateY: 0 }));

    this.setData({
      isSortMode: true,
      query: "",
      filterKind: "all",
      filterTag: "",
      grouped: false,
      dragItems: rows,
    });

    this.recompute();
  },
  onTouchStart(e: WechatMiniprogram.TouchEvent) {
    const index = Number(e.currentTarget.dataset.index);

    this.clearPressTimer();
    this.setData({ draggingIndex: index, touchStartY: e.touches[0].clientY });

    this.pressTimer = setTimeout(() => {
      if (this.data.draggingIndex === index) {
        this.setData({ isDragging: true });
      }
    }, LONG_PRESS_MS);
  },
  onTouchMove(e: WechatMiniprogram.TouchEvent) {
    const deltaY = e.touches[0].clientY - this.data.touchStartY;

    if (!this.data.isDragging) {
      // 长按生效前的明显位移视为滚动：取消待触发的拖动高亮
      if (Math.abs(deltaY) > MOVE_CANCEL_PX) {
        this.setData({ draggingIndex: -1 });
      }

      return;
    }

    const index = this.data.draggingIndex;

    if (index < 0) {
      return;
    }

    // 只写被拖动行：整份 dragItems（含全部密钥字段）不再随每个 touchmove 序列化到视图层
    this.setData({ [`dragItems[${index}].translateY`]: deltaY });
  },
  onTouchEnd() {
    this.clearPressTimer();

    const index = this.data.draggingIndex;

    if (index < 0 || !this.data.isDragging) {
      this.setData({ draggingIndex: -1, isDragging: false });

      return;
    }

    const rows = this.data.dragItems;
    const to = dropIndex(index, rows[index].translateY, rows.length);

    if (to === index) {
      this.setData({
        [`dragItems[${index}].translateY`]: 0,
        draggingIndex: -1,
        isDragging: false,
      });

      return;
    }

    this.setData({
      dragItems: moveItem(rows, index, to).map((row) => ({
        ...row,
        translateY: 0,
      })),
      draggingIndex: -1,
      isDragging: false,
    });
  },
  // 来电 / 系统弹窗会打断 touch 序列：与松手同口径收尾，避免 isDragging 卡住后再也拖不动
  onTouchCancel() {
    this.onTouchEnd();
  },
  clearPressTimer() {
    if (this.pressTimer !== null) {
      clearTimeout(this.pressTimer);
      this.pressTimer = null;
    }
  },
  onUnload() {
    this.clearPressTimer();
  },
  async saveSort() {
    const ordered = this.data.dragItems;
    const sortItems = ordered.map((item, index) => ({
      id: item.id,
      sort: ordered.length - 1 - index,
    }));

    try {
      await withLoading("保存中...", () => api.sort(sortItems));
      // 服务端成功后才覆盖缓存顺序
      applySort(ordered.map((item) => item.id));

      this.setData({
        isSortMode: false,
        dragItems: [],
        draggingIndex: -1,
        isDragging: false,
      });

      this.recompute();
    } catch (e: unknown) {
      // 服务端未变更：缓存顺序就是进入排序时的顺序，重新派生视图即可恢复
      this.setData({
        isSortMode: false,
        dragItems: [],
        draggingIndex: -1,
        isDragging: false,
      });

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
