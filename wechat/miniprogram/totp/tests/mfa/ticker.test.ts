/**
 * 秒级 ticker（utils/ticker.ts）测试：订阅计数、单定时器复用、退订回收、异常隔离与整秒通知。
 * 只用一个真实等待（≤1.1s）覆盖通知链路，其余断言走同步计数。
 */
import { describe, expect, it } from "bun:test";
import { onSecond, subscriberCount, timerActive } from "../../src/utils/ticker";

describe("ticker", () => {
  it("returnsIdempotentUnsubscribe", () => {
    const base = subscriberCount();
    const off = onSecond(() => undefined);

    expect(subscriberCount()).toBe(base + 1);

    off();
    off();

    expect(subscriberCount()).toBe(base);
  });

  it("stopsTimerWhenLastSubscriberLeaves", () => {
    expect(subscriberCount()).toBe(0);
    expect(timerActive()).toBe(0);

    const offA = onSecond(() => undefined);
    const offB = onSecond(() => undefined);

    // 多订阅者共用同一个定时器
    expect(subscriberCount()).toBe(2);
    expect(timerActive()).toBe(1);

    offA();
    expect(timerActive()).toBe(1);

    offB();
    expect(subscriberCount()).toBe(0);
    expect(timerActive()).toBe(0);
  });

  it("notifiesEverySubscriberOnWholeSecondAndIsolatesThrowingOne", async () => {
    const seen: number[] = [];

    const offBad = onSecond(() => {
      throw new Error("boom");
    });
    const offGood = onSecond((now) => {
      seen.push(now);
    });

    await new Promise((resolve) => setTimeout(resolve, 1100));

    offBad();
    offGood();

    expect(seen.length).toBeGreaterThanOrEqual(1);
    // 通知时间落在整秒边界附近（同一 tick 内所有订阅者共享同一个 now）
    expect(Math.abs(seen[0] % 1000)).toBeLessThan(100);
    expect(subscriberCount()).toBe(0);
    expect(timerActive()).toBe(0);
  });
});
