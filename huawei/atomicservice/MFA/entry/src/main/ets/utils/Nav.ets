import { AppStorageV2 } from '@kit.ArkUI';
import { AppPagesName } from '../App';
import { State } from '../models/Auth';
import { LoginPageParams } from '../pages/Login';

const pages = (): NavPathStack => AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;

// 跳转到登录页重新认证：登录页已在栈中时忽略，避免重复入栈；不传 state 时由登录页自行判断当前认证状态
export const redirectLoginPage = (state?: State): void => {
  const allPathName: string[] = pages().getAllPathName();

  if (allPathName.includes(AppPagesName.LOGIN.toString())) {
    return;
  }

  const param: LoginPageParams | null =
    'undefined' === typeof state ? null : { forceAuthorizationState: state };

  pages().pushPathByName(AppPagesName.LOGIN, param);
};
