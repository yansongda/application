import { describe, expect, it } from '@ohos/hypium';
import { AuthSnapshot, computeAuthState, REFRESH_AHEAD_MS } from '../main/ets/utils/AuthStatePolicy';
import { State } from '../main/ets/types/Session';

const NOW: number = 1700000000000;
const FAR: number = NOW + 100 * REFRESH_AHEAD_MS;

const snapshot = (accessToken: string | undefined, refreshToken: string | undefined,
  expiredAtMs: number | undefined): AuthSnapshot => {
  return { accessToken: accessToken, refreshToken: refreshToken, expiredAtMs: expiredAtMs };
};

export default function authStatePolicyTest(): void {
  describe('authStatePolicy', () => {
    it('empty_when_tokens_missing', 0, () => {
      expect(computeAuthState(snapshot(undefined, 'refresh', FAR), NOW)).assertEqual(State.EMPTY_AUTHORIZATION);
      expect(computeAuthState(snapshot('', 'refresh', FAR), NOW)).assertEqual(State.EMPTY_AUTHORIZATION);
      expect(computeAuthState(snapshot('access', undefined, FAR), NOW)).assertEqual(State.EMPTY_AUTHORIZATION);
      expect(computeAuthState(snapshot('access', '', FAR), NOW)).assertEqual(State.EMPTY_AUTHORIZATION);
    });

    it('empty_when_expiry_invalid', 0, () => {
      // expired_in 缺失 / 非数字会让 _expiredAt 变成 Invalid Date，5 分钟续期判定永远为 false，
      // 表现为「登录成功却反复回登录页」——这里必须判成 EMPTY 而不是 NORMAL
      expect(computeAuthState(snapshot('access', 'refresh', undefined), NOW)).assertEqual(State.EMPTY_AUTHORIZATION);
      expect(computeAuthState(snapshot('access', 'refresh', Number.NaN), NOW)).assertEqual(State.EMPTY_AUTHORIZATION);
    });

    it('need_refresh_inside_ahead_window', 0, () => {
      expect(computeAuthState(snapshot('access', 'refresh', NOW + REFRESH_AHEAD_MS), NOW))
        .assertEqual(State.NEED_REFRESH);
      // 已经过期也属于需要续期
      expect(computeAuthState(snapshot('access', 'refresh', NOW - 1), NOW)).assertEqual(State.NEED_REFRESH);
    });

    it('normal_outside_ahead_window', 0, () => {
      expect(computeAuthState(snapshot('access', 'refresh', NOW + REFRESH_AHEAD_MS + 1), NOW))
        .assertEqual(State.NORMAL);
    });

    it('never_guesses_refresh_token_expiry', 0, () => {
      // 本地判定不再猜服务端 refresh_token 的有效期（曾用「29 天」魔法常量），
      // 即使 access_token 的到期时间非常遥远，结论也只可能是 NORMAL / NEED_REFRESH / EMPTY
      expect(computeAuthState(snapshot('access', 'refresh', NOW + 365 * 24 * 60 * 60 * 1000), NOW))
        .assertEqual(State.NORMAL);
    });
  });
}
