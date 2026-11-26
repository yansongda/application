// 全应用**唯一**的秒级时钟：一个定时器 + 一个 `@Trace nowMs`。
//
// 为什么不是每条目各自定时（历史实现见 PR 前的 `ItemRuntime.schedule()`）：
// - 每条目 1 个 setInterval + 1 个 setTimeout = 2N 个定时器，实际间隔 ≥1000ms 会累积漂移，
//   各条目相位随运行时间发散 → 每秒产生 N 次分散在不同帧的刷新，而不是 1 次；
// - 每条目还要单独维护「起/停/恢复」状态机（页面隐藏、退后台、登录页在栈中……），
//   任何一处漏配对就是定时器泄漏或验证码冻结。
// 现在：时间只有一个来源，倒计时是 `nowMs` 的派生值（见 `ItemRuntime#remaining`），
// 没有任何「每秒递减的本地计数」需要维护，也就不存在漂移与配对问题。
//
// 不变量（改动前请确认）：
// - `attach()/detach()` **只由 EntryAbility 的前后台回调驱动**（与页面生命周期无关），
//   页面切换不得起停时钟，否则「详情页压住列表」这类正常场景会被误判成「该停表」；
// - `nowMs` 是 `@Trace` 且**每秒只写一次** —— UI 侧只能派生读取（`ItemRuntime#remaining`），
//   禁止在别处再写它，也禁止为「进度条」引入第二份每秒变动的状态；
// - 时钟只负责「时间」，不负责算码：算码订阅在 `EntryAbility` 里接到 `ItemsRuntime#onTick`；
// - 退后台后 `nowMs` 保持最后值（页面不可见），回前台 `attach()` 会立即用当前时刻补一次。
import { AppStorageV2 } from '@kit.ArkUI';
import { AlignedTicker, SystemTimerSource } from '../../utils/Ticker';

@ObservedV2
export class Clock {
  // 当前时刻（毫秒）。每秒写一次；UI 通过 ItemRuntime 的派生 getter 读取。
  @Trace nowMs: number = Date.now();

  // 全应用只有一个 ticker：1s 粒度、对齐整秒边界
  private readonly _ticker: AlignedTicker = new AlignedTicker(new SystemTimerSource());
  // 算码订阅（由 EntryAbility 接线），与 UI 派生读取是两条独立通道
  private _listeners: ((nowMs: number) => void)[] = [];

  constructor() {
    // ticker 的唯一订阅者就是本类：先落 nowMs 再通知订阅者，
    // 保证订阅者算码时读到的 `remaining` 与本 tick 属于同一时刻
    this._ticker.subscribe((nowMs: number): void => {
      this.publish(nowMs);
    });
  }

  static instance(): Clock {
    return AppStorageV2.connect(Clock, () => new Clock())!;
  }

  // 回前台 / 冷启动：立即推进一次（不必等下一个整秒）并开始计时
  attach(): void {
    this._ticker.start();
  }

  // 退后台：只停调度，保留订阅关系（订阅是进程级的，重新挂接没有额外状态）
  detach(): void {
    this._ticker.stop();
  }

  // 订阅每整秒回调；返回幂等退订函数
  subscribe(listener: (nowMs: number) => void): () => void {
    this._listeners.push(listener);

    return (): void => {
      const index: number = this._listeners.indexOf(listener);

      if (index >= 0) {
        this._listeners.splice(index, 1);
      }
    };
  }

  private publish(nowMs: number): void {
    // 先写状态、再通知订阅者：UI 侧读到的 `nowMs` 与订阅者算码用的时刻一致
    this.nowMs = nowMs;

    const listeners: ((nowMs: number) => void)[] = [...this._listeners];

    for (const listener of listeners) {
      try {
        listener(nowMs);
      } catch (e) {
        // 订阅者异常不能打断时钟本身；失败提示由 ItemsRuntime 统一上报
      }
    }
  }
}
