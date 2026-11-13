// 登录页路由参数（叶子类型）：Nav / SessionGuard 只依赖这个类型，不需要 import 页面，
// 避免 `utils → pages/Login → utils` 的反向依赖。
import { State } from './Session';

export interface LoginPageParams {
  forceAuthorizationState: State;
}
