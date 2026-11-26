// 秒级统一 ticker 的**调度逻辑**（定时器注入，无 ArkUI 依赖，可在 `entry/src/test` 单测）。
//
// 不变量（改动前请确认）：
// - **粒度 1s**：前提是所有 TOTP 周期都是正整数秒（见 `utils/Totp.ets#normalizePeriod`）。
// - 用递归 `schedule(delay)` **对齐整秒边界**（delay = periodMs - now % periodMs），
//   不能用朴素 `setInterval(periodMs)`：定时器实际间隔只会 ≥ 请求值，朴素写法会累积漂移，
//   表现为「倒计时归零」与「验证码翻转」逐渐错开。
// - **任意时刻最多 1 个定时器**：`schedule()` 先 `cancel()` 再登记，重复 `start()` / 运行期订阅都不会叠加。
// - 停止后不得自动复活：tick 回调里 `publish()` 可能触发调用方 `stop()`（退后台），
//   因此重新登记前必须检查 `_running`。
// - 订阅者异常**就地吞掉**：一个条目算码失败不能拖垮其它条目，异常提示由订阅者自己负责。
// - 没有订阅者时不保留定时器（`unsubscribe` 到 0 立即 `cancel` 并停止）。
//
// 与 `utils/dialog/WindowCoordinator.ets` 同风格：系统调用（定时器）经接口注入，
// 本文件只保留可判定的调度规则，因此能在没有真机的情况下覆盖「对齐 / 复用 / 回收 / 异常隔离」。
export interface TimerSource {
  schedule(delayMs: number, action: () => void): number;

  cancel(handle: number): void;

  now(): number;
}

// 系统定时器实现：setTimeout / clearTimeout 是 JS 全局能力，不依赖 ArkUI
export class SystemTimerSource implements TimerSource {
  schedule(delayMs: number, action: () => void): number {
    return setTimeout(action, delayMs);
  }

  cancel(handle: number): void {
    clearTimeout(handle);
  }

  now(): number {
    return Date.now();
  }
}

export class AlignedTicker {
  private readonly _source: TimerSource;
  private readonly _periodMs: number;
  private _handle: number | undefined = undefined;
  private _listeners: ((nowMs: number) => void)[] = [];
  private _running: boolean = false;

  constructor(source: TimerSource, periodMs: number = 1000) {
    this._source = source;
    this._periodMs = periodMs;
  }

  subscribe(listener: (nowMs: number) => void): () => void {
    this._listeners.push(listener);
    // 运行期新增订阅者时补一个定时器（已有定时器时 schedule 会先取消，不会叠加）
    this.schedule();

    return (): void => {
      this.remove(listener);
    };
  }

  // 开始计时（幂等）：先立即通知一次，调用方不必等下一个整秒（回前台立刻刷新验证码）
  start(): void {
    this._running = true;
    this.publish();
    this.schedule();
  }

  stop(): void {
    this._running = false;
    this.cancel();
  }

  private cancel(): void {
    if ('undefined' === typeof this._handle) {
      return;
    }

    this._source.cancel(this._handle);
    this._handle = undefined;
  }

  private schedule(): void {
    // 先取消：保证任何时刻最多一个定时器（重复 start / 运行期 subscribe 都不会叠加）
    this.cancel();

    if (!this._running || this._listeners.length === 0) {
      return;
    }

    const delayMs: number = this._periodMs - (this._source.now() % this._periodMs);

    this._handle = this._source.schedule(delayMs, (): void => {
      // 先清句柄再通知：回调里可能 stop() / 退订，此时不能再去 cancel 已执行的句柄
      this._handle = undefined;

      this.publish();
      // publish 里可能已 stop()：schedule 内部会检查 _running，不会把定时器复活
      this.schedule();
    });
  }

  private publish(): void {
    const nowMs: number = this._source.now();
    // 复制一份再遍历：订阅者可能在回调里退订（直接遍历会被 splice 打乱）
    const listeners: ((nowMs: number) => void)[] = [...this._listeners];

    for (const listener of listeners) {
      try {
        listener(nowMs);
      } catch (e) {
        // 订阅者自行负责兜底提示；这里只保证其它订阅者继续被通知
      }
    }
  }

  private remove(listener: (nowMs: number) => void): void {
    const index: number = this._listeners.indexOf(listener);

    if (index >= 0) {
      this._listeners.splice(index, 1);
    }

    if (this._listeners.length === 0) {
      this.stop();
    }
  }
}
