/**
 * 应用锁的锁定判定策略：纯函数，不依赖任何 wx / 系统 API，可在 Bun 下直接单测。
 * 阈值常量同时导出，供单测用「常量 ± 1」表达边界，避免阈值调整后用例仍写死旧字面量而失真。
 *
 * 判定顺序（与设计文档 §3.5.2 一致）：
 * enabled=false                  → 永不锁
 * enabled=true + 冷启动          → 页面 onShow 时 locked=true
 * !pendingCheck（未退后台再回前台）→ 不锁
 * lastHideAt 缺失（从未退后台）    → 不锁
 * 时钟回拨（now < lastHideAt）    → 不锁
 * now - lastHideAt >= timeout    → 锁
 */
export const LOCK_TIMEOUT_MS = 60_000;

export interface LockCheckInput {
  enabled: boolean;
  coldStart: boolean;
  pendingCheck: boolean;
  lastHideAt?: number;
  now: number;
  timeoutMs?: number;
}

const shouldLock = (input: LockCheckInput): boolean => {
  const timeoutMs = input.timeoutMs ?? LOCK_TIMEOUT_MS;

  if (!input.enabled) {
    return false;
  }

  if (input.coldStart) {
    return true;
  }

  if (!input.pendingCheck) {
    return false;
  }

  if (input.lastHideAt === undefined) {
    return false;
  }

  if (input.now < input.lastHideAt) {
    return false;
  }

  return input.now - input.lastHideAt >= timeoutMs;
};

export { shouldLock };
