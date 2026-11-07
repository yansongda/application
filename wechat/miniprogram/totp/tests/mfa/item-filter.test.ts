/**
 * 首页搜索 / 筛选 / 置顶排序 / 分组纯函数测试（语义对齐华为 utils/ItemFilter.ets）。
 */
import { describe, expect, it } from "bun:test";
import {
  collectTagStats,
  collectTags,
  countPinned,
  filterItems,
  groupItems,
  ItemFilterKind,
  ItemGroupKind,
  type ItemView,
  sortPinnedFirst,
} from "../../src/utils/item-filter";

const item = (
  id: string,
  issuer: string,
  username: string,
  tags: string[],
  pinned = false,
): ItemView => ({ id, issuer, username, tags, pinned });

const SAMPLE: ItemView[] = [
  item("1", "GitHub", "alice@example.com", ["工作"]),
  item("2", "Google", "alice@example.com", ["个人", "工作"], true),
  item("3", "ACME", "bob@example.com", []),
  item("4", "DISCORD", "Alice", ["游戏"]),
];

describe("item-filter", () => {
  it("query_blankTokensMatchAll", () => {
    expect(filterItems(SAMPLE, ItemFilterKind.ALL, "", "   ")).toHaveLength(4);
    expect(filterItems(SAMPLE, ItemFilterKind.ALL, "", "")).toHaveLength(4);
  });

  it("query_caseInsensitiveMatchesIssuerUsernameTag", () => {
    expect(
      filterItems(SAMPLE, ItemFilterKind.ALL, "", "github").map((i) => i.id),
    ).toEqual(["1"]);
    expect(
      filterItems(SAMPLE, ItemFilterKind.ALL, "", "ALICE").map((i) => i.id),
    ).toEqual(["1", "2", "4"]);
    expect(
      filterItems(SAMPLE, ItemFilterKind.ALL, "", "工作").map((i) => i.id),
    ).toEqual(["1", "2"]);
  });

  it("query_tokensAreAnd", () => {
    expect(
      filterItems(SAMPLE, ItemFilterKind.ALL, "", "alice 工作").map(
        (i) => i.id,
      ),
    ).toEqual(["1", "2"]);
    // bob 只命中 3，github 只命中 1：无交集
    expect(
      filterItems(SAMPLE, ItemFilterKind.ALL, "", "bob github"),
    ).toHaveLength(0);
  });

  it("query_multipleSpacesAreTokens", () => {
    expect(
      filterItems(SAMPLE, ItemFilterKind.ALL, "", "alice  工作").map(
        (i) => i.id,
      ),
    ).toEqual(["1", "2"]);
  });

  it("filter_pinnedKind", () => {
    expect(
      filterItems(SAMPLE, ItemFilterKind.PINNED, "", "").map((i) => i.id),
    ).toEqual(["2"]);
  });

  it("filter_tagKind", () => {
    expect(
      filterItems(SAMPLE, ItemFilterKind.TAG, "工作", "").map((i) => i.id),
    ).toEqual(["1", "2"]);
    expect(
      filterItems(SAMPLE, ItemFilterKind.TAG, "游戏", "").map((i) => i.id),
    ).toEqual(["4"]);
    expect(filterItems(SAMPLE, ItemFilterKind.TAG, "不存在", "")).toHaveLength(
      0,
    );
  });

  it("filter_combinesWithQuery", () => {
    expect(
      filterItems(SAMPLE, ItemFilterKind.TAG, "工作", "google").map(
        (i) => i.id,
      ),
    ).toEqual(["2"]);
  });

  it("sortPinnedFirst_stablePartition", () => {
    const sorted = sortPinnedFirst(SAMPLE);

    expect(sorted.map((i) => i.id)).toEqual(["2", "1", "3", "4"]);
    // 稳定性：置顶项与非置顶项各自保持输入的相对顺序
    expect(sorted.filter((i) => i.pinned).map((i) => i.id)).toEqual(
      SAMPLE.filter((i) => i.pinned).map((i) => i.id),
    );
    expect(sorted.filter((i) => !i.pinned).map((i) => i.id)).toEqual(
      SAMPLE.filter((i) => !i.pinned).map((i) => i.id),
    );
  });

  it("group_pinnedTagUnassigned", () => {
    const groups = groupItems(SAMPLE);

    expect(groups).toEqual([
      { kind: ItemGroupKind.PINNED, tag: "", ids: ["2"] },
      { kind: ItemGroupKind.TAG, tag: "工作", ids: ["1"] },
      { kind: ItemGroupKind.TAG, tag: "游戏", ids: ["4"] },
      { kind: ItemGroupKind.UNASSIGNED, tag: "", ids: ["3"] },
    ]);
  });

  it("group_pinnedNotDuplicatedIntoTags", () => {
    const pinnedWithTag = [
      item("p", "X", "y", ["工作"], true),
      item("a", "X", "y", ["工作"]),
    ];
    const groups = groupItems(pinnedWithTag);

    expect(groups[0]).toEqual({
      kind: ItemGroupKind.PINNED,
      tag: "",
      ids: ["p"],
    });
    expect(groups[1]).toEqual({
      kind: ItemGroupKind.TAG,
      tag: "工作",
      ids: ["a"],
    });
    expect(groups.flatMap((g) => g.ids)).toEqual(["p", "a"]);
  });

  it("group_usesFirstTagPerItem", () => {
    const multiTag = [item("m", "X", "y", ["工作", "个人"])];
    const groups = groupItems(multiTag);

    expect(groups).toEqual([
      { kind: ItemGroupKind.TAG, tag: "工作", ids: ["m"] },
    ]);
  });

  it("group_emptyAndAllPinned", () => {
    expect(groupItems([])).toEqual([]);
    expect(
      groupItems([
        item("a", "X", "y", [], true),
        item("b", "X", "y", [], true),
      ]),
    ).toEqual([{ kind: ItemGroupKind.PINNED, tag: "", ids: ["a", "b"] }]);
  });

  it("collectTags_firstAppearanceOrderDeduplicated", () => {
    expect(collectTags(SAMPLE)).toEqual(["工作", "个人", "游戏"]);
    expect(collectTags([item("a", "X", "y", [""])])).toEqual([]);
  });

  it("collectTagStats_orderAndCounts", () => {
    expect(collectTagStats(SAMPLE)).toEqual([
      { tag: "工作", count: 2 },
      { tag: "个人", count: 1 },
      { tag: "游戏", count: 1 },
    ]);
  });

  it("collectTagStats_duplicateTagsWithinItemCountOnce", () => {
    const dup = [item("a", "X", "y", ["工作", "工作", "个人"])];
    expect(collectTagStats(dup)).toEqual([
      { tag: "工作", count: 1 },
      { tag: "个人", count: 1 },
    ]);
  });

  it("countPinned", () => {
    expect(countPinned(SAMPLE)).toBe(1);
    expect(countPinned([])).toBe(0);
  });
});
