import { describe, expect, test } from "bun:test";
import { syncTabBarSelected, TAB_BAR_INDEX } from "../../src/utils/tab-bar";

interface Spy {
  calls: { selected: number }[];
}

// 构造页面实例桩：getTabBar 的返回值为 null 代表组件尚未 attached
const hostWith = (tabBar: { instance?: Spy } | null): unknown => {
  const spy: Spy = { calls: [] };
  const instance = {
    setData: (data: { selected: number }) => {
      spy.calls.push(data);
    },
  };

  if (tabBar === null) {
    return { getTabBar: () => null };
  }

  tabBar.instance = spy;

  return { getTabBar: () => instance };
};

describe("syncTabBarSelected", () => {
  test("页面没有 getTabBar 时静默返回", () => {
    expect(() => syncTabBarSelected({}, TAB_BAR_INDEX.totp)).not.toThrow();
    expect(() =>
      syncTabBarSelected(undefined, TAB_BAR_INDEX.user),
    ).not.toThrow();
  });

  test("自定义 tabBar 组件尚未 attached 时静默返回", () => {
    expect(() =>
      syncTabBarSelected(hostWith(null), TAB_BAR_INDEX.totp),
    ).not.toThrow();
  });

  test("把选中态同步到 tabBar 实例", () => {
    const holder: { instance?: Spy } = {};
    syncTabBarSelected(hostWith(holder), TAB_BAR_INDEX.user);

    expect(holder.instance?.calls).toEqual([{ selected: TAB_BAR_INDEX.user }]);
  });

  test("索引与 app.json tabBar.list 顺序一致", () => {
    // list[0] = pages/totp/index，list[1] = pages/user/index
    expect(TAB_BAR_INDEX.totp).toBe(0);
    expect(TAB_BAR_INDEX.user).toBe(1);
  });
});
