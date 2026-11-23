// 导航栈状态查询（叶子工具）：全应用共享同一个 NavPathStack，只做「读」，
// 不参与 push/pop 策略（策略在 SessionGuard / 页面自己手里）。
import { AppStorageV2 } from '@kit.ArkUI';
import { AppPagesName } from '../App';

export const navPages = (): NavPathStack => AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;

// 登录页是否在栈中（登录页永远 push 在栈顶，等价于「登录页是否可见」）
export const loginInStack = (): boolean => navPages().getAllPathName().includes(AppPagesName.LOGIN.toString());

// 当前栈顶页面名（登录页做 pop 兜底时用：用户可能已用返回手势关掉自己）
export const topPageName = (): string | undefined => {
  const names: string[] = navPages().getAllPathName();

  return names.length > 0 ? names[names.length - 1] : undefined;
};
