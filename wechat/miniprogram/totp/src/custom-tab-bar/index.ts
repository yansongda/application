import logger from "@utils/logger";
import { TAB_BAR_INDEX } from "@utils/tab-bar";
import type { Tap } from "types/wechat";

interface TabBarItem {
  pagePath: string;
  text: string;
  icon: string;
  index: number;
}

interface TabTapDataset {
  index: string;
}

// 顺序与 app.json tabBar.list 严格一致；自定义 tabBar 用 t-icon 渲染，无需 iconPath 图片
const LIST: TabBarItem[] = [
  {
    index: TAB_BAR_INDEX.totp,
    pagePath: "/pages/totp/index",
    text: "TOTP",
    icon: "lock-on",
  },
  {
    index: TAB_BAR_INDEX.user,
    pagePath: "/pages/user/index",
    text: "我的",
    icon: "user",
  },
];

Component({
  data: {
    selected: TAB_BAR_INDEX.totp,
    list: LIST,
  },
  methods: {
    onTabTap(e: Tap<TabTapDataset, TabTapDataset>) {
      const index = Number(e.currentTarget.dataset.index);
      const target = LIST.find((item) => item.index === index);

      // 点击当前 tab 不重复 switchTab，避免无谓的页面 onShow
      if (target === undefined || index === this.data.selected) {
        return;
      }

      wx.switchTab({ url: target.pagePath }).catch((err: unknown) => {
        logger.warning("切换 tab 失败", err);
      });
    },
  },
});
