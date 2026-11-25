/**
 * 秒级统一 ticker：整个小程序只有一个定时器，所有订阅者在同一整秒边界被通知。
 *
 * 不变量（改动前请确认）：
 * - **粒度 1s**，前提是所有 TOTP 周期都是正整数秒。`@yansongda/miniprogram-otp` 内部按
 *   `floor(ms/1000)` 计算 step / remaining，period 必须为正整数秒；若将来支持亚秒周期，
 *   这里需要降粒度或按最小周期间隔调度。
 * - 用递归 `setTimeout(1000 - now % 1000)` **对齐整秒边界**，不能用朴素 `setInterval(1000)`
 *   （会累积漂移，验证码翻转与倒计时会逐渐滞后）。
 * - 订阅者必须在组件 `detached` / `pageLifetimes.hide`（页面侧 `onHide` / `onUnload`）
 *   时退订，否则页面销毁后仍会每秒回调。
 *
 * 本文件不依赖 logger（logger 顶层执行 wx 调用，纯逻辑模块不得引入），
 * 订阅者异常就地吞掉，避免一个卡片算码失败拖垮其它卡片。
 */
type TickHandler = (now: number) => void;

const handlers = new Set<TickHandler>();
let timer: number | null = null;

const schedule = (): void => {
  timer = setTimeout(
    () => {
      timer = null;

      const now = Date.now();

      for (const handler of [...handlers]) {
        try {
          handler(now);
        } catch (_e: unknown) {
          // 订阅者自行负责兜底提示；这里只保证其它订阅者继续被通知
        }
      }

      if (handlers.size > 0) {
        schedule();
      }
    },
    1000 - (Date.now() % 1000),
  );
};

/** 订阅整秒回调，返回**幂等**的退订函数。 */
const onSecond = (handler: TickHandler): (() => void) => {
  handlers.add(handler);

  if (timer === null) {
    schedule();
  }

  return () => {
    handlers.delete(handler);

    if (handlers.size === 0 && timer !== null) {
      clearTimeout(timer);
      timer = null;
    }
  };
};

/** 当前订阅者数量：仅供单测断言，生产代码不要依赖。 */
const subscriberCount = (): number => handlers.size;

/** 是否还有定时器在跑（0 或 1）：仅供单测断言。 */
const timerActive = (): number => (timer === null ? 0 : 1);

export { onSecond, subscriberCount, timerActive };
