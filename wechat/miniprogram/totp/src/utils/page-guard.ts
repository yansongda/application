/**
 * 页面级应用锁守卫：把 12 个页面里逐字重复的 onShow 判定收敛成一次调用。
 *
 * 约定（与 utils/app-lock.ts 的状态机配套）：
 * - 页面 `data.locked` 初始值仍由各页自己声明，本模块只负责「判定 + 按需 setData」，
 *   不做对象展开注入，避免与页面自身 data 相互覆盖。
 * - `guardOnShow` 返回 true 表示当前处于锁定态，调用方必须立即 return（不发请求、不启动计时）。
 * - 解锁成功后调用 `guardOnUnlocked` 解除遮罩；需要恢复取数/计时的页面再自行续跑 onShow。
 */
import { syncOnPageShow } from "./app-lock";

interface LockGuardHost {
  data: { locked: boolean };
  setData: (data: { locked: boolean }) => void;
}

const guardOnShow = (page: LockGuardHost): boolean => {
  const locked = syncOnPageShow();

  if (locked !== page.data.locked) {
    page.setData({ locked });
  }

  return locked;
};

const guardOnUnlocked = (page: LockGuardHost): void => {
  page.setData({ locked: false });
};

export { guardOnShow, guardOnUnlocked };
