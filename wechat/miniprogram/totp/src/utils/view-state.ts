/**
 * 首页列表视图状态（筛选 / 分组）的纯逻辑 + wx 存储读写。
 * 与华为 models/totp/ListViewState.ets 语义对齐：筛选与分组互斥（筛选生效即退出分组，
 * 进入分组即清空筛选）；搜索词只影响本地渲染、不落盘。
 * 本文件不依赖 logger（logger 顶层执行 wx 调用，纯逻辑模块不得引入），
 * 存储读写失败静默返回 false：视图状态丢失不影响使用。
 */
import { STORAGE } from "../constant/app";

export type ViewFilterKind = "all" | "pinned" | "tag";

export interface ViewState {
  kind: ViewFilterKind;
  tag: string;
  grouped: boolean;
}

export const DEFAULT_VIEW_STATE: ViewState = {
  kind: "all",
  tag: "",
  grouped: false,
};

// 落盘结构：kind 为可读字符串（磁盘数据可读，增删枚举不会串值）；grouped 与筛选互斥由解码规则保证
export interface StoredViewState {
  kind: string;
  tag: string;
  grouped: boolean;
}

const sameView = (a: ViewState, b: ViewState): boolean => {
  return a.kind === b.kind && a.tag === b.tag && a.grouped === b.grouped;
};

// 生效视图 → 磁盘结构
const encodeViewState = (state: ViewState): StoredViewState => {
  return { kind: state.kind, tag: state.tag, grouped: state.grouped };
};

// 磁盘结构 → 生效视图：缺失 / 类型不符 / kind 非法 / tag 为空一律回落默认（脏数据不能让首页空列表）；
// grouped 与筛选互斥：筛选生效时以筛选为准（否则会渲染出「分组视图 + 标签筛选」的组合，得到空组）
const decodeViewState = (raw: unknown): ViewState => {
  if (typeof raw !== "object" || raw === null) {
    return { ...DEFAULT_VIEW_STATE };
  }

  const stored = raw as Partial<StoredViewState>;
  let kind: ViewFilterKind = "all";
  let tag = "";

  if (stored.kind === "pinned") {
    kind = "pinned";
  } else if (
    stored.kind === "tag" &&
    typeof stored.tag === "string" &&
    stored.tag.length > 0
  ) {
    kind = "tag";
    tag = stored.tag;
  }

  const grouped = kind === "all" && stored.grouped === true;

  return { kind, tag, grouped };
};

// 选择筛选即退出分组视图（state 参数仅为对齐调用方签名，返回值不依赖入参）
const applyFilter = (
  _state: ViewState,
  kind: ViewFilterKind,
  tag: string,
): ViewState => {
  return { kind, tag, grouped: false };
};

// 进入分组视图时清空筛选（分组按标签聚合，叠加筛选会得到空组）；退出分组保持筛选不变
const applyGrouped = (state: ViewState, grouped: boolean): ViewState => {
  if (!grouped) {
    return { ...state, grouped: false };
  }

  return { kind: "all", tag: "", grouped: true };
};

// 清空筛选（搜索词不在本模块状态内；分组开关保持现状，与华为 ListViewState.clearFilter 一致）
const clearFilter = (state: ViewState): ViewState => {
  return { kind: "all", tag: "", grouped: state.grouped };
};

// 从待渲染条目提取标签（按首次出现顺序去重，空标签忽略）
const collectTagsFrom = (items: Array<{ tags: string[] }>): string[] => {
  const tags: string[] = [];

  for (const item of items) {
    for (const tag of item.tags) {
      if (tag.length > 0 && !tags.includes(tag)) {
        tags.push(tag);
      }
    }
  }

  return tags;
};

const countPinnedFrom = (items: Array<{ pinned: boolean }>): number => {
  let count = 0;

  for (const item of items) {
    if (item.pinned) {
      count++;
    }
  }

  return count;
};

// 刷新后清理已失效的视图状态：标签被删空、置顶项被取消时回到「全部」；
// 条目为空整体回落默认视图（全部 + 平铺）。分组不需要清理：没有标签时所有条目归入「未分类」。
// 返回是否发生变更——变更后调用方需要回写，否则下次启动会再加载一遍失效状态。
const syncView = (
  state: ViewState,
  items: Array<{ tags: string[]; pinned: boolean }>,
): { state: ViewState; changed: boolean } => {
  if (items.length === 0) {
    const next = { ...DEFAULT_VIEW_STATE };

    return { state: next, changed: !sameView(state, next) };
  }

  let kind = state.kind;
  let tag = state.tag;

  if (kind === "tag" && !collectTagsFrom(items).includes(tag)) {
    kind = "all";
    tag = "";
  }

  if (kind === "pinned" && countPinnedFrom(items) === 0) {
    kind = "all";
    tag = "";
  }

  const next: ViewState = { kind, tag, grouped: state.grouped };

  return { state: next, changed: !sameView(state, next) };
};

// 冷启动恢复：读不到 / 脏数据一律回落默认视图（「全部 + 平铺」），不影响启动
const readViewState = (): ViewState => {
  return decodeViewState(wx.getStorageSync(STORAGE.INDEX_VIEW_STATE));
};

// 落盘当前视图。写失败只静默返回 false（视图状态丢失不影响使用）；
// 不记录日志：本模块不依赖 logger
const saveViewState = (state: ViewState): boolean => {
  try {
    wx.setStorageSync(STORAGE.INDEX_VIEW_STATE, encodeViewState(state));

    return true;
  } catch {
    // storage 写入失败（容量 / 隐私模式等）：视图状态丢失不影响使用
    return false;
  }
};

// 注销账号后清理：筛选/分组是针对被删账号的标签产生的，避免下一个账号继承
const clearViewState = (): void => {
  wx.removeStorageSync(STORAGE.INDEX_VIEW_STATE);
};

export {
  applyFilter,
  applyGrouped,
  clearFilter,
  clearViewState,
  decodeViewState,
  encodeViewState,
  readViewState,
  saveViewState,
  syncView,
};
