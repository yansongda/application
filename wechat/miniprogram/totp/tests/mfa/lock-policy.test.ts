/**
 * 应用锁锁定判定策略测试（设计文档 §3.5.2）：边界用 LOCK_TIMEOUT_MS ± 1 表达。
 */
import { describe, expect, it } from "bun:test";
import { LOCK_TIMEOUT_MS, shouldLock } from "../../src/utils/lock-policy";

const base = {
  enabled: true,
  coldStart: false,
  pendingCheck: true,
  lastHideAt: 1000,
  now: 1000,
};

describe("lock-policy", () => {
  it("disabledNeverLocks", () => {
    expect(
      shouldLock({
        ...base,
        enabled: false,
        coldStart: true,
        now: 1000 + LOCK_TIMEOUT_MS,
      }),
    ).toBe(false);
  });

  it("coldStartAlwaysLocks", () => {
    expect(shouldLock({ ...base, coldStart: true, pendingCheck: false })).toBe(
      true,
    );
    expect(shouldLock({ ...base, coldStart: true, now: 0 })).toBe(true);
  });

  it("noPendingCheckDoesNotLock", () => {
    expect(
      shouldLock({ ...base, pendingCheck: false, now: 1000 + LOCK_TIMEOUT_MS }),
    ).toBe(false);
  });

  it("missingLastHideAtDoesNotLock", () => {
    expect(
      shouldLock({
        ...base,
        lastHideAt: undefined,
        now: 2000 + LOCK_TIMEOUT_MS,
      }),
    ).toBe(false);
  });

  it("belowTimeoutDoesNotLock", () => {
    expect(shouldLock({ ...base, now: 1000 + LOCK_TIMEOUT_MS - 1 })).toBe(
      false,
    );
  });

  it("atTimeoutLocks", () => {
    expect(shouldLock({ ...base, now: 1000 + LOCK_TIMEOUT_MS })).toBe(true);
  });

  it("beyondTimeoutLocks", () => {
    expect(shouldLock({ ...base, now: 1000 + LOCK_TIMEOUT_MS + 1 })).toBe(true);
  });

  it("clockRollbackDoesNotLock", () => {
    expect(shouldLock({ ...base, now: 999 })).toBe(false);
  });

  it("customTimeoutRespected", () => {
    expect(shouldLock({ ...base, timeoutMs: 5000, now: 1000 + 5000 - 1 })).toBe(
      false,
    );
    expect(shouldLock({ ...base, timeoutMs: 5000, now: 1000 + 5000 })).toBe(
      true,
    );
  });
});
