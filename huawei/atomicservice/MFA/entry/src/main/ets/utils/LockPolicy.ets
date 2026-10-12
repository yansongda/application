// 锁定与验证防抖策略：纯判定函数，不依赖任何 ArkUI / 系统 API，可在 entry/src/test 本地单测。
export const LOCK_TIMEOUT_MS: number = 60000;
export const VERIFY_DEBOUNCE_MS: number = 3000;
export function shouldRelock(appLock: boolean, backgroundAt: number | undefined, now: number,
  timeout: number = LOCK_TIMEOUT_MS): boolean {
  // 未开启应用锁、无退后台时间戳（冷启动）、时钟回拨（now < backgroundAt）一律不重锁
  if (!appLock || 'undefined' === typeof backgroundAt || now < backgroundAt) { return false; }
  return now - backgroundAt >= timeout;
}
export function shouldDebounceVerify(finishedAt: number | undefined, now: number,
  debounce: number = VERIFY_DEBOUNCE_MS): boolean {
  // finishedAt = 上一次验证**结束**时间戳；从未验证过（undefined）或时钟回拨 → 不算命中防抖，
  // 必须放行，否则首次验证会被自身防抖挡住，应用锁会把用户永久锁死
  if ('undefined' === typeof finishedAt || now < finishedAt) { return false; }
  return now - finishedAt < debounce;
}
