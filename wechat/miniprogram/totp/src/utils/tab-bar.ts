// 自定义 tabBar（app.json 中 tabBar.custom = true）不会随 switchTab 自动切换高亮，
// 必须由每个 tab 页在 onShow 时主动把 selected 指回自身（微信自定义 tabBar 约定）。
// getTabBar 的类型声明只挂在 Component 实例上，页面侧用最小结构断言，避免引入 any。

interface TabBarInstance {
  setData: (data: { selected: number }) => void;
}

interface TabBarHost {
  getTabBar?: () => TabBarInstance | null | undefined;
}

// 与 app.json tabBar.list 顺序严格一致（custom-tab-bar/index.ts 的 LIST 同源）
const TAB_BAR_INDEX = {
  totp: 0,
  user: 1,
} as const;

const syncTabBarSelected = (host: unknown, selected: number): void => {
  const page = host as TabBarHost | null | undefined;

  if (page === null || page === undefined) {
    return;
  }

  if (typeof page.getTabBar !== "function") {
    return;
  }

  const tabBar = page.getTabBar();

  if (tabBar === null || tabBar === undefined) {
    return;
  }

  tabBar.setData({ selected });
};

export { syncTabBarSelected, TAB_BAR_INDEX };
