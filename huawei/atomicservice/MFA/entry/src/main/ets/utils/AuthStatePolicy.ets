// 认证状态判定（纯逻辑）：只吃「本地 token 快照 + 当前时间」，不碰持久化 / 网络 / ArkUI，
// 因此可以在 `entry/src/test` 里直接单测（参考 `utils/AppLockPolicy.ets` 的写法）。
//
// 为什么要有这一层：原先 `Authorization.state()` 把判定和 `dateformat` 混在一起，
// 还内联了「refresh_token 30 天有效期、提前 1 天刷新」这类**服务端契约**的猜测（29 天魔法常量）。
// 服务端早已用 1005/1006 明确告知 refresh_token 是否失效，本地再猜一次只会制造耦合：
//   1) 29 天阈值任何一次服务端调整都会悄悄失效；
//   2) `REFRESH_TOKEN_EXPIRED` 被判成「需要重新登录」，而实际上 refresh_token 可能还有效（白白多一次授权）。
// 现在本地只判「access_token 是否临近过期」，refresh_token 的有效性完全交给服务端。
import { State } from '../types/Session';

// access_token 提前刷新窗口：剩这么久就认为需要续期，避免请求卡在过期边界上
export const REFRESH_AHEAD_MS: number = 5 * 60 * 1000;

export interface AuthSnapshot {
  accessToken?: string;
  refreshToken?: string;
  // access_token 到期时间（epoch 毫秒）
  expiredAtMs?: number;
}

// 返回 State.NORMAL / NEED_REFRESH / EMPTY_AUTHORIZATION。
// 注意：**永远不会返回 REFRESH_TOKEN_EXPIRED**——该状态只由 Http 响应拦截器（1005/1006）给出，
// 枚举值保留是为了让「服务端判定」与「本地推测」在类型上仍然可区分。
export const computeAuthState = (snapshot: AuthSnapshot, nowMs: number): State => {
  if ('undefined' === typeof snapshot.accessToken || 0 === snapshot.accessToken.length ||
    'undefined' === typeof snapshot.refreshToken || 0 === snapshot.refreshToken.length ||
    'undefined' === typeof snapshot.expiredAtMs || !Number.isFinite(snapshot.expiredAtMs)) {
    return State.EMPTY_AUTHORIZATION;
  }

  if (snapshot.expiredAtMs - nowMs <= REFRESH_AHEAD_MS) {
    return State.NEED_REFRESH;
  }

  return State.NORMAL;
};
