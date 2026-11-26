/**
 * 首页视图模型（utils/totp-view.ts）测试：映射、筛选、置顶优先、分组、视图状态清理。
 * 纯函数，无需 wx 桩。
 */
import { describe, expect, it } from "bun:test";
import type { CacheItem } from "../../src/types/totp";
import { ItemGroupKind } from "../../src/utils/item-filter";
import {
  type BuildListViewInput,
  buildListView,
  toItemView,
  toListItem,
} from "../../src/utils/totp-view";
import { DEFAULT_VIEW_STATE, type ViewState } from "../../src/utils/view-state";

const item = (id: string, overrides: Partial<CacheItem> = {}): CacheItem => ({
  id,
  issuer: `issuer-${id}`,
  username: `user-${id}`,
  secret: "JBSWY3DPEHPK3PXP",
  period: 30,
  digits: 6,
  algorithm: "SHA1",
  tags: [],
  pinned: false,
  ...overrides,
});

const build = (input: Partial<BuildListViewInput> & { items: CacheItem[] }) =>
  buildListView({
    viewState: { ...DEFAULT_VIEW_STATE },
    query: "",
    isSortMode: false,
    ...input,
  });

describe("totp-view mapping", () => {
  it("toListItem_truncatesAndCarriesTotpFields", () => {
    const view = toListItem(item("a", { issuer: "0123456789" }));

    expect(view.issuer).toBe("0123456...");
    expect(view.secret).toBe("JBSWY3DPEHPK3PXP");
    expect(view.period).toBe(30);
    expect(view.digits).toBe(6);
    expect(view.algorithm).toBe("SHA1");
  });

  it("toListItem_defaultsMissingTagsAndPinned", () => {
    const view = toListItem({
      id: "a",
      issuer: "x",
      username: "y",
      secret: "s",
      period: 30,
    });

    expect(view.tags).toEqual([]);
    expect(view.pinned).toBe(false);
  });

  it("toItemView_keepsFullText", () => {
    const view = toItemView(item("a", { issuer: "0123456789" }));

    expect(view.issuer).toBe("0123456789");
    expect(view).not.toHaveProperty("secret");
  });
});

describe("buildListView", () => {
  const items = [
    item("a", { tags: ["工作"], pinned: false }),
    item("b", { tags: ["个人", "工作"], pinned: true }),
    item("c", { tags: [], pinned: false }),
  ];

  it("sortsPinnedFirstAndCounts", () => {
    const { model } = build({ items });

    expect(model.visibleItems.map((v) => v.id)).toEqual(["b", "a", "c"]);
    expect(model.totalCount).toBe(3);
    expect(model.pinnedCount).toBe(1);
    expect(model.menuStats).toEqual({
      total: 3,
      pinned: 1,
      tags: [
        { tag: "工作", count: 2 },
        { tag: "个人", count: 1 },
      ],
    });
    expect(model.filterLabel).toBe("筛选");
    expect(model.viewActive).toBe(false);
  });

  it("filtersByQueryAcrossIssuerUsernameAndTags", () => {
    const byIssuer = build({ items, query: "issuer-a" });

    expect(byIssuer.model.visibleItems.map((v) => v.id)).toEqual(["a"]);

    const byTag = build({ items, query: "个人" });

    expect(byTag.model.visibleItems.map((v) => v.id)).toEqual(["b"]);
  });

  it("filtersByPinned", () => {
    const { model } = build({
      items,
      viewState: { ...DEFAULT_VIEW_STATE, kind: "pinned" },
    });

    expect(model.visibleItems.map((v) => v.id)).toEqual(["b"]);
    expect(model.filterLabel).toBe("置顶");
    expect(model.viewActive).toBe(true);
  });

  it("filtersByTag", () => {
    const { model } = build({
      items,
      viewState: { ...DEFAULT_VIEW_STATE, kind: "tag", tag: "工作" },
    });

    expect(model.visibleItems.map((v) => v.id)).toEqual(["b", "a"]);
    expect(model.filterLabel).toBe("#工作");
  });

  it("groupsByPinnedThenTagsThenUnassigned", () => {
    const { model } = build({
      items,
      viewState: { ...DEFAULT_VIEW_STATE, grouped: true },
    });

    expect(model.visibleItems).toEqual([]);
    expect(model.groups.map((g) => [g.kind, g.title, g.ids])).toEqual([
      [ItemGroupKind.PINNED, "置顶", ["b"]],
      [ItemGroupKind.TAG, "工作", ["a"]],
      [ItemGroupKind.UNASSIGNED, "未分类", ["c"]],
    ]);
    expect(model.groups[0].items.map((v) => v.id)).toEqual(["b"]);
    expect(model.filterLabel).toBe("分组");
  });

  it("sortModeKeepsCacheOrderAndBypassesGrouping", () => {
    const { model } = build({
      items,
      isSortMode: true,
      viewState: { ...DEFAULT_VIEW_STATE, grouped: true },
    });

    expect(model.visibleItems.map((v) => v.id)).toEqual(["a", "b", "c"]);
    expect(model.groups).toEqual([]);
    expect(model.grouped).toBe(false);
  });

  it("dropsStaleTagFilterAndReportsChange", () => {
    const stale: ViewState = { kind: "tag", tag: "已删除", grouped: false };
    const result = build({ items, viewState: stale });

    expect(result.viewStateChanged).toBe(true);
    expect(result.viewState.kind).toBe("all");
    expect(result.model.visibleItems).toHaveLength(3);
  });

  it("resetsToDefaultWhenNoItems", () => {
    const result = build({
      items: [],
      viewState: { kind: "pinned", tag: "", grouped: true },
    });

    expect(result.viewStateChanged).toBe(true);
    expect(result.viewState).toEqual(DEFAULT_VIEW_STATE);
    expect(result.model.totalCount).toBe(0);
    expect(result.model.visibleItems).toEqual([]);
    expect(result.model.groups).toEqual([]);
  });

  it("keepsStateWhenNothingChanged", () => {
    const result = build({
      items,
      viewState: { ...DEFAULT_VIEW_STATE, kind: "all" },
    });

    expect(result.viewStateChanged).toBe(false);
  });
});

describe("buildListView full-text search", () => {
  it("matchesTextBeyondDisplayTruncation", () => {
    const long = item("a", {
      issuer: "Google Cloud Platform",
      username: "user@example.com",
    });

    // 展示层仍截断，但搜索按完整文本命中（此前只匹配截断后的 "Google ..."）
    const byIssuer = build({ items: [long], query: "platform" });

    expect(byIssuer.model.visibleItems.map((v) => v.id)).toEqual(["a"]);
    expect(byIssuer.model.visibleItems[0].issuer).toContain("...");

    const byUsername = build({ items: [long], query: "example" });

    expect(byUsername.model.visibleItems.map((v) => v.id)).toEqual(["a"]);
  });
});
