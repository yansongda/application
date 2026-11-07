/**
 * 首页视图状态（筛选 / 分组）测试：解码回落、筛选/分组互斥、失效清理、存储读写。
 * view-state.ts 顶层不调用 wx（仅函数体内），本测试文件在顶层注入最小 wx 桩即可。
 */
import { beforeEach, describe, expect, it } from "bun:test";
import { STORAGE } from "../../src/constant/app";
import {
  applyFilter,
  applyGrouped,
  clearFilter,
  clearViewState,
  DEFAULT_VIEW_STATE,
  decodeViewState,
  encodeViewState,
  readViewState,
  saveViewState,
  syncView,
} from "../../src/utils/view-state";

// 最小 wx 桩：getStorageSync / setStorageSync / removeStorageSync
const storage = new Map<string, unknown>();
globalThis.wx = {
  getStorageSync: (key: string) => storage.get(key),
  setStorageSync: (key: string, value: unknown) => {
    storage.set(key, value);
  },
  removeStorageSync: (key: string) => {
    storage.delete(key);
  },
} as unknown as WechatMiniprogram.Wx;

beforeEach(() => {
  storage.clear();
});

describe("view-state", () => {
  it("decode_missingOrInvalidFallsBackToDefault", () => {
    for (const raw of [undefined, null, "", 42, [], "all"]) {
      expect(decodeViewState(raw)).toEqual(DEFAULT_VIEW_STATE);
    }

    expect(decodeViewState({})).toEqual(DEFAULT_VIEW_STATE);
    // 对象存在但 kind 非法 / tag 为空：kind 回落 all；grouped 独立校验并保留（对齐华为 decodeView）
    expect(decodeViewState({ kind: "bogus", tag: "x", grouped: true })).toEqual(
      {
        kind: "all",
        tag: "",
        grouped: true,
      },
    );
    expect(decodeViewState({ kind: "tag" })).toEqual(DEFAULT_VIEW_STATE);
    expect(decodeViewState({ kind: "tag", tag: "", grouped: true })).toEqual({
      kind: "all",
      tag: "",
      grouped: true,
    });
  });

  it("decode_restoresEachKind", () => {
    expect(decodeViewState({ kind: "all", tag: "", grouped: false })).toEqual({
      kind: "all",
      tag: "",
      grouped: false,
    });
    expect(
      decodeViewState({ kind: "pinned", tag: "", grouped: false }),
    ).toEqual({
      kind: "pinned",
      tag: "",
      grouped: false,
    });
    expect(
      decodeViewState({ kind: "tag", tag: "工作", grouped: false }),
    ).toEqual({
      kind: "tag",
      tag: "工作",
      grouped: false,
    });
  });

  it("decode_groupedMutuallyExclusiveWithFilter", () => {
    // 分组与筛选互斥：磁盘数据两者都成立时以筛选为准
    expect(
      decodeViewState({ kind: "tag", tag: "工作", grouped: true }),
    ).toEqual({
      kind: "tag",
      tag: "工作",
      grouped: false,
    });
    expect(decodeViewState({ kind: "pinned", tag: "", grouped: true })).toEqual(
      {
        kind: "pinned",
        tag: "",
        grouped: false,
      },
    );
  });

  it("encode_roundTrips", () => {
    const state = { kind: "tag" as const, tag: "工作", grouped: false };
    expect(decodeViewState(encodeViewState(state))).toEqual(state);
    expect(encodeViewState(DEFAULT_VIEW_STATE)).toEqual({
      kind: "all",
      tag: "",
      grouped: false,
    });
  });

  it("applyFilter_exitsGrouped", () => {
    expect(
      applyFilter({ kind: "all", tag: "", grouped: true }, "tag", "工作"),
    ).toEqual({
      kind: "tag",
      tag: "工作",
      grouped: false,
    });
  });

  it("applyGrouped_clearsFilterWhenEntering", () => {
    expect(
      applyGrouped({ kind: "tag", tag: "工作", grouped: false }, true),
    ).toEqual({
      kind: "all",
      tag: "",
      grouped: true,
    });
    expect(
      applyGrouped({ kind: "tag", tag: "工作", grouped: false }, false),
    ).toEqual({
      kind: "tag",
      tag: "工作",
      grouped: false,
    });
  });

  it("clearFilter_keepsGrouped", () => {
    expect(clearFilter({ kind: "tag", tag: "工作", grouped: true })).toEqual({
      kind: "all",
      tag: "",
      grouped: true,
    });
  });

  it("syncView_emptyItemsResetsToDefaultFlat", () => {
    const r = syncView({ kind: "tag", tag: "工作", grouped: true }, []);

    expect(r.state).toEqual(DEFAULT_VIEW_STATE);
    expect(r.changed).toBe(true);
  });

  it("syncView_emptyItemsNoChangeWhenAlreadyDefault", () => {
    const r = syncView(DEFAULT_VIEW_STATE, []);

    expect(r.state).toEqual(DEFAULT_VIEW_STATE);
    expect(r.changed).toBe(false);
  });

  it("syncView_removesStaleTagFilter", () => {
    const items = [{ tags: ["个人"], pinned: false }];
    const r = syncView({ kind: "tag", tag: "工作", grouped: false }, items);

    expect(r.state).toEqual({ kind: "all", tag: "", grouped: false });
    expect(r.changed).toBe(true);
  });

  it("syncView_keepsExistingTagFilter", () => {
    const items = [{ tags: ["工作"], pinned: false }];
    const r = syncView({ kind: "tag", tag: "工作", grouped: false }, items);

    expect(r.state).toEqual({ kind: "tag", tag: "工作", grouped: false });
    expect(r.changed).toBe(false);
  });

  it("syncView_removesPinnedFilterWhenNoPinnedLeft", () => {
    const items = [{ tags: [], pinned: false }];
    const r = syncView({ kind: "pinned", tag: "", grouped: false }, items);

    expect(r.state).toEqual({ kind: "all", tag: "", grouped: false });
    expect(r.changed).toBe(true);
  });

  it("syncView_keepsPinnedFilter", () => {
    const items = [{ tags: [], pinned: true }];
    const r = syncView({ kind: "pinned", tag: "", grouped: false }, items);

    expect(r.state).toEqual({ kind: "pinned", tag: "", grouped: false });
    expect(r.changed).toBe(false);
  });

  it("storage_saveReadClearRoundTrip", () => {
    expect(readViewState()).toEqual(DEFAULT_VIEW_STATE);

    const state = { kind: "tag" as const, tag: "工作", grouped: false };
    expect(saveViewState(state)).toBe(true);
    expect(storage.get(STORAGE.INDEX_VIEW_STATE)).toEqual({
      kind: "tag",
      tag: "工作",
      grouped: false,
    });
    expect(readViewState()).toEqual(state);

    clearViewState();
    expect(storage.has(STORAGE.INDEX_VIEW_STATE)).toBe(false);
    expect(readViewState()).toEqual(DEFAULT_VIEW_STATE);
  });
});
