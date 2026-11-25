/**
 * 拖拽排序几何（utils/sort-order.ts）测试：行高、松手落位边界、重排不可变性。
 */
import { describe, expect, it } from "bun:test";
import { dropIndex, moveItem, ROW_HEIGHT } from "../../src/utils/sort-order";

describe("sort-order", () => {
  it("rowHeight_is_100px", () => {
    expect(ROW_HEIGHT).toBe(100);
  });

  it("dropIndex_keepsPositionWithoutMovement", () => {
    expect(dropIndex(2, 0, 10)).toBe(2);
  });

  it("dropIndex_roundsToNearestRow", () => {
    expect(dropIndex(1, 100, 10)).toBe(2);
    expect(dropIndex(1, 49, 10)).toBe(1);
    expect(dropIndex(1, 51, 10)).toBe(2);
    expect(dropIndex(1, -100, 10)).toBe(0);
    expect(dropIndex(1, -51, 10)).toBe(0);
  });

  it("dropIndex_clampsToRange", () => {
    expect(dropIndex(0, -1000, 3)).toBe(0);
    expect(dropIndex(2, 1000, 3)).toBe(2);
    expect(dropIndex(0, 0, 0)).toBe(0);
  });

  it("moveItem_reordersBothDirections", () => {
    expect(moveItem(["a", "b", "c"], 0, 2)).toEqual(["b", "c", "a"]);
    expect(moveItem(["a", "b", "c"], 2, 0)).toEqual(["c", "a", "b"]);
  });

  it("moveItem_ignoresNoopAndOutOfRange", () => {
    const list = ["a", "b", "c"];

    expect(moveItem(list, 1, 1)).toEqual(list);
    expect(moveItem(list, -1, 1)).toEqual(list);
    expect(moveItem(list, 3, 1)).toEqual(list);
  });

  it("moveItem_doesNotMutateInput", () => {
    const list = ["a", "b", "c"];

    moveItem(list, 0, 2);

    expect(list).toEqual(["a", "b", "c"]);
  });
});
