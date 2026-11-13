import { AppStorageV2 } from '@kit.ArkUI';
import { AppPagesName } from '../App';
import { State } from '../models/Auth';
import { LoginPageParams } from '../pages/Login';
import { AuthGate } from './AuthGate';
import { Dialog } from './PromptAction';

// 跳登录页前的让位时间：先关掉残留 loading / 重试框，再入栈，避免两个弹窗同屏
const REDIRECT_GAP_MS: number = 200;

const pages = (): NavPathStack => AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;

const loginInStack = (): boolean => pages().getAllPathName().includes(AppPagesName.LOGIN.toString());

// 跳转到登录页重新认证：登录页已在栈中时忽略，避免重复入栈；不传 state 时由登录页自行判断当前认证状态。
// 自动跳转会先清掉已有弹窗并延迟入栈：拦截器在响应回调里同步触发，调用方的失败清理（关 loading /
// 开重试框）还没跑完，直接 push 会让「上个页面的弹窗 + 登录页 loading」叠在一起。
export const redirectLoginPage = (state?: State): void => {
  if (loginInStack()) {
    return;
  }

  if (!AuthGate.allow(Date.now())) {
    return;
  }

  Dialog.closeAll();

  setTimeout(() => {
    AuthGate.finish();

    if (loginInStack()) {
      return;
    }

    // 等待期间调用方可能已经打开了失败框：入栈前再清一次，避免它盖在登录页上方
    Dialog.closeAll();

    const param: LoginPageParams | null =
      'undefined' === typeof state ? null : { forceAuthorizationState: state };

    pages().pushPathByName(AppPagesName.LOGIN, param);
  }, REDIRECT_GAP_MS);
};
