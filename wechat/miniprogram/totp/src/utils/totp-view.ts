/**
 * 首页列表视图模型：把「缓存条目 → 卡片渲染条目 → 筛选 / 置顶优先 / 分组 → 渲染数据」
 * 整条链路收进纯函数，页面只负责取数与 `setData`。
 *
 * 零 wx / logger 依赖，可在 Bun 下直接单测（见 `tests/mfa/totp-view.test.ts`）。
 * 语义与华为元服务首页一致：筛选与分组互斥、置顶优先、分组顺序 = 置顶 → 各标签（首次出现）→ 未分类。
 */

import type { CacheItem } from "../types/totp";
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
} from "./item-filter";
import { substr } from "./string";
import { syncView, type ViewFilterKind, type ViewState } from "./view-state";

/** 卡片渲染条目：ItemView 基础上携带算码所需字段（直接作为 `app-totp-item` 的 props）。 */
export interface ListItemView extends ItemView {
  secret: string;
  period: number;
  digits?: number;
  algorithm?: string;
}

/** 分组渲染条目：标题 + 组内 id + 组内卡片条目。 */
export interface ListGroupView {
  kind: ItemGroupKind;
  tag: string;
  title: string;
  ids: string[];
  items: ListItemView[];
}

export interface ListMenuStats {
  total: number;
  pinned: number;
  tags: TagStat[];
}

/** 首页 `setData` 的视图模型：键名与页面 `data` 一一对应。 */
export interface ListViewModel {
  visibleItems: ListItemView[];
  groups: ListGroupView[];
  menuStats: ListMenuStats;
  filterKind: ViewFilterKind;
  filterTag: string;
  grouped: boolean;
  filterLabel: string;
  viewActive: boolean;
  totalCount: number;
  pinnedCount: number;
}

export interface BuildListViewInput {
  items: CacheItem[];
  viewState: ViewState;
  query: string;
  isSortMode: boolean;
}

export interface BuildListViewResult {
  model: ListViewModel;
  /** 清理后的视图状态：标签被删空 / 置顶清零 / 条目清空时回落默认视图。 */
  viewState: ViewState;
  /** 视图状态发生变化时为 true，调用方需要回写磁盘，否则下次启动会再加载失效视图。 */
  viewStateChanged: boolean;
}

/** 缓存条目 → 通用视图条目（首页派生、标签页建议共用）。 */
export const toItemView = (item: CacheItem): ItemView => {
  return {
    id: item.id,
    issuer: item.issuer,
    username: item.username,
    tags: item.tags ?? [],
    pinned: item.pinned === true,
  };
};

/** 缓存条目 → 首页卡片条目（发行方 / 用户名做确定性截断，保持与旧版展示一致）。 */
export const toListItem = (item: CacheItem): ListItemView => {
  return {
    id: item.id,
    issuer: substr(item.issuer, 7),
    username: substr(item.username, 50),
    tags: item.tags ?? [],
    pinned: item.pinned === true,
    secret: item.secret,
    period: item.period,
    digits: item.digits,
    algorithm: item.algorithm,
  };
};

const toFilterKind = (kind: ViewFilterKind): ItemFilterKind => {
  if (kind === "pinned") {
    return ItemFilterKind.PINNED;
  }

  return kind === "tag" ? ItemFilterKind.TAG : ItemFilterKind.ALL;
};

// 工具栏按钮文案：分组 > 置顶 > 标签 > 默认「筛选」
const filterLabelOf = (state: ViewState): string => {
  if (state.grouped) {
    return "分组";
  }

  if (state.kind === "pinned") {
    return "置顶";
  }

  if (state.kind === "tag" && state.tag.length > 0) {
    return `#${state.tag}`;
  }

  return "筛选";
};

const groupTitleOf = (kind: ItemGroupKind, tag: string): string => {
  if (kind === ItemGroupKind.PINNED) {
    return "置顶";
  }

  return kind === ItemGroupKind.UNASSIGNED ? "未分类" : tag;
};

export const buildListView = (
  input: BuildListViewInput,
): BuildListViewResult => {
  // 过滤 / 分组 / 统计一律用完整文本：截断只影响展示，不应让「搜索完整发行方名称」落空
  const views = input.items.map(toItemView);
  const displayById = new Map<string, ListItemView>(
    input.items.map((item) => [item.id, toListItem(item)]),
  );
  const synced = syncView(input.viewState, views);
  const state = synced.state;

  const filtered = filterItems(
    views,
    toFilterKind(state.kind),
    state.tag,
    input.query,
  );
  // 排序模式下按缓存顺序展示，不做置顶优先，避免「刚拖到下面又被置顶规则顶回顶部」
  const ordered = input.isSortMode ? filtered : sortPinnedFirst(filtered);
  const grouped = state.grouped && !input.isSortMode;
  const displayOf = (id: string): ListItemView[] => {
    const display = displayById.get(id);

    return display === undefined ? [] : [display];
  };
  const groups: ListGroupView[] = grouped
    ? groupItems(ordered).map((group) => ({
        kind: group.kind,
        tag: group.tag,
        title: groupTitleOf(group.kind, group.tag),
        ids: group.ids,
        items: group.ids.flatMap(displayOf),
      }))
    : [];
  const pinnedCount = countPinned(views);

  return {
    model: {
      visibleItems: grouped
        ? []
        : ordered.flatMap((view) => displayOf(view.id)),
      groups,
      menuStats: {
        total: views.length,
        pinned: pinnedCount,
        tags: collectTagStats(views),
      },
      filterKind: state.kind,
      filterTag: state.tag,
      grouped,
      filterLabel: filterLabelOf(state),
      viewActive: state.grouped || state.kind !== "all",
      totalCount: input.items.length,
      pinnedCount,
    },
    viewState: state,
    viewStateChanged: synced.changed,
  };
};
