import { describe, expect, it } from '@ohos/hypium';
import { OtpAlgorithm, TOTP } from '@yansongda/otp';
import { IItemConfig } from '../main/ets/types/Item';
import {
  DEFAULT_ALGORITHM,
  DEFAULT_DIGITS,
  DEFAULT_PERIOD,
  normalizeAlgorithm,
  normalizeConfig,
  normalizeDigits,
  normalizePeriod,
  remainingOf,
  stepOf
} from '../main/ets/utils/Totp';
import { AlignedTicker, TimerSource } from '../main/ets/utils/Ticker';

// 时钟基准（2023-11-15T06:13:20Z）：与真实时区无关，所有断言都是相对值
const NOW: number = 1700000000000;
const RFC_SECRET: string = 'JBSWY3DPEHPK3PXP';

interface FakeTask {
  handle: number;
  delayMs: number;
  action: () => void;
}

// 注入式定时器：不依赖真实时间，可精确断言「对齐整秒 / 单定时器 / 退订回收 / 异常隔离」
class FakeTimerSource implements TimerSource {
  nowMs: number = 0;
  private _tasks: FakeTask[] = [];
  private _nextHandle: number = 1;

  schedule(delayMs: number, action: () => void): number {
    const handle: number = this._nextHandle;

    this._nextHandle += 1;
    this._tasks.push({ handle: handle, delayMs: delayMs, action: action });

    return handle;
  }

  cancel(handle: number): void {
    this._tasks = this._tasks.filter((task: FakeTask): boolean => task.handle !== handle);
  }

  now(): number {
    return this.nowMs;
  }

  get pending(): number {
    return this._tasks.length;
  }

  // 最近一次登记任务的延迟（未登记时为 -1）
  get lastDelayMs(): number {
    return this._tasks.length > 0 ? this._tasks[this._tasks.length - 1].delayMs : -1;
  }

  // 执行最早登记的任务，并把时间推到期（模拟定时器到点）
  fireNext(): void {
    const task: FakeTask | undefined = this._tasks.shift();

    if ('undefined' === typeof task) {
      return;
    }

    this.nowMs += task.delayMs;
    task.action();
  }
}

export default function totpRuntimeTest(): void {
  describe('totp_params', () => {
    it('period_keeps_positive_integers', 0, () => {
      expect(normalizePeriod(30)).assertEqual(30);
      expect(normalizePeriod(45)).assertEqual(45);
      expect(normalizePeriod(1)).assertEqual(1);
    });

    it('period_falls_back_for_dirty_values', 0, () => {
      // 脏缓存：0 / 负数 / 小数 / 非数字 / Infinity / 缺失，一律回落默认 30s
      expect(normalizePeriod(0)).assertEqual(DEFAULT_PERIOD);
      expect(normalizePeriod(-30)).assertEqual(DEFAULT_PERIOD);
      expect(normalizePeriod(2.5)).assertEqual(DEFAULT_PERIOD);
      expect(normalizePeriod(NaN)).assertEqual(DEFAULT_PERIOD);
      expect(normalizePeriod(Infinity)).assertEqual(DEFAULT_PERIOD);
      expect(normalizePeriod(undefined)).assertEqual(DEFAULT_PERIOD);
    });

    it('digits_only_accepts_6_to_8', 0, () => {
      expect(normalizeDigits(6)).assertEqual(6);
      expect(normalizeDigits(7)).assertEqual(7);
      expect(normalizeDigits(8)).assertEqual(8);
      expect(normalizeDigits(5)).assertEqual(DEFAULT_DIGITS);
      expect(normalizeDigits(9)).assertEqual(DEFAULT_DIGITS);
      expect(normalizeDigits(6.5)).assertEqual(DEFAULT_DIGITS);
      expect(normalizeDigits(undefined)).assertEqual(DEFAULT_DIGITS);
    });

    it('algorithm_only_accepts_known_names', 0, () => {
      expect(normalizeAlgorithm('SHA1')).assertEqual(OtpAlgorithm.SHA1);
      expect(normalizeAlgorithm('SHA256')).assertEqual(OtpAlgorithm.SHA256);
      expect(normalizeAlgorithm('SHA512')).assertEqual(OtpAlgorithm.SHA512);
      // 后端只会下发大写；小写 / 未知值一律按默认算法，绝不把脏值透传给库
      expect(normalizeAlgorithm('sha256')).assertEqual(DEFAULT_ALGORITHM);
      expect(normalizeAlgorithm('MD5')).assertEqual(DEFAULT_ALGORITHM);
      expect(normalizeAlgorithm(undefined)).assertEqual(DEFAULT_ALGORITHM);
    });

    it('config_is_normalized_once', 0, () => {
      const dirty: IItemConfig = { period: 0, digits: 4, algorithm: 'MD5', secret: RFC_SECRET };
      const config = normalizeConfig(dirty);

      expect(config.period).assertEqual(DEFAULT_PERIOD);
      expect(config.digits).assertEqual(DEFAULT_DIGITS);
      expect(config.algorithm).assertEqual(DEFAULT_ALGORITHM);
      expect(config.secret).assertEqual(RFC_SECRET);
    });

    it('config_without_secret_has_no_secret_field', 0, () => {
      // secret 缺失 = 本端不可算码（须回退服务端），不能被归一化成空串
      const config = normalizeConfig({ period: 30 });

      expect(config.secret).assertUndefined();
    });

    it('config_missing_entirely_uses_defaults', 0, () => {
      const config = normalizeConfig(undefined);

      expect(config.period).assertEqual(DEFAULT_PERIOD);
      expect(config.digits).assertEqual(DEFAULT_DIGITS);
      expect(config.algorithm).assertEqual(DEFAULT_ALGORITHM);
    });
  });

  describe('totp_progress', () => {
    it('remaining_is_within_one_period', 0, () => {
      // remaining ∈ [1, period]：窗口起点是 period，窗口末尾是 1，永远不出现 0
      // （0 会让进度条 value/total = 0 且「剩余 0 秒」在 UI 上停留一整秒）
      expect(remainingOf(0, 30)).assertEqual(30);
      expect(remainingOf(999, 30)).assertEqual(30);
      expect(remainingOf(1000, 30)).assertEqual(29);
      expect(remainingOf(29000, 30)).assertEqual(1);
      expect(remainingOf(30000, 30)).assertEqual(30);
    });

    it('matches_library_remaining', 0, () => {
      // 与 @yansongda/otp 内部算法对齐：倒计时与「验证码翻转」必须用同一套取模，
      // 否则 period 非 60 约数（45s）或时区偏移非整小时（+05:30）时两者会错开
      const totp: TOTP = new TOTP({ secret: RFC_SECRET, period: 45 });
      const samples: number[] = [0, 1, 999, 1000, 44000, 45000, 89999, 90000, NOW, NOW + 12345];

      samples.forEach((sample: number) => {
        expect(remainingOf(sample, 45)).assertEqual(totp.remaining(sample));
      });
    });

    it('step_increments_at_boundary', 0, () => {
      const period: number = 45;
      const remaining: number = remainingOf(NOW, period);
      const boundary: number = NOW + remaining * 1000;

      // 走到窗口边界：remaining 回到 period，step 恰好 +1
      expect(remainingOf(boundary, period)).assertEqual(period);
      expect(stepOf(boundary, period)).assertEqual(stepOf(NOW, period) + 1);
      // 边界前 1ms 仍属于上一格
      expect(stepOf(boundary - 1, period)).assertEqual(stepOf(NOW, period));
    });

    it('step_is_independent_of_timezone_offset', 0, () => {
      // 时区偏移只是 nowMs 的常量偏移，不影响「格数差」的整数性（+05:30 与 UTC 得到同一格边界）
      const period: number = 30;
      const offset: number = 19800000; // +05:30

      expect(remainingOf(NOW, period)).assertEqual(remainingOf(NOW + offset, period));
    });
  });

  describe('aligned_ticker', () => {
    it('aligns_to_whole_second', 0, () => {
      const source: FakeTimerSource = new FakeTimerSource();

      source.nowMs = NOW + 250; // 距整秒 250ms → 首次调度应是 750ms 后

      const ticker: AlignedTicker = new AlignedTicker(source);

      ticker.subscribe(() => {
      });
      ticker.start();

      expect(source.lastDelayMs).assertEqual(750);
      expect(source.pending).assertEqual(1);
    });

    it('reuses_single_timer', 0, () => {
      const source: FakeTimerSource = new FakeTimerSource();
      const ticker: AlignedTicker = new AlignedTicker(source);

      ticker.subscribe(() => {
      });
      ticker.start();
      ticker.start();
      // 运行期再订阅也不能叠出第二个定时器
      ticker.subscribe(() => {
      });

      expect(source.pending).assertEqual(1);
    });

    it('notifies_on_each_tick_and_reschedules', 0, () => {
      const source: FakeTimerSource = new FakeTimerSource();

      source.nowMs = NOW + 250;

      const ticker: AlignedTicker = new AlignedTicker(source);
      let ticks: number = 0;

      ticker.subscribe(() => {
        ticks += 1;
      });
      ticker.start(); // 立即通知一次
      source.fireNext();

      expect(ticks).assertEqual(2);
      // 对齐后每次都正好 1000ms（不会像 setInterval 那样累积漂移）
      expect(source.lastDelayMs).assertEqual(1000);
      expect(source.nowMs).assertEqual(NOW + 1000);
    });

    it('stop_cancels_pending_timer', 0, () => {
      const source: FakeTimerSource = new FakeTimerSource();
      const ticker: AlignedTicker = new AlignedTicker(source);

      ticker.subscribe(() => {
      });
      ticker.start();
      ticker.stop();

      expect(source.pending).assertEqual(0);
      expect(ticker.ticking).assertFalse();
    });

    it('unsubscribe_recycles_timer', 0, () => {
      const source: FakeTimerSource = new FakeTimerSource();
      const ticker: AlignedTicker = new AlignedTicker(source);
      const off: () => void = ticker.subscribe(() => {
      });

      ticker.start();
      expect(source.pending).assertEqual(1);

      // 退订到 0 个订阅者：定时器立即回收，不留后台空转
      off();
      expect(source.pending).assertEqual(0);
      expect(ticker.listenerCount).assertEqual(0);
    });

    it('stop_during_tick_does_not_resurrect', 0, () => {
      const source: FakeTimerSource = new FakeTimerSource();
      const ticker: AlignedTicker = new AlignedTicker(source);

      // 退后台（stop）可能就是在某个 tick 回调里被调用的：不能让 tick 末尾的
      // 重新登记把定时器重新拉起来，否则进程后台空转
      ticker.subscribe(() => {
        ticker.stop();
      });
      ticker.start();

      expect(source.pending).assertEqual(0);
      expect(ticker.ticking).assertFalse();
    });

    it('isolates_listener_exception', 0, () => {
      const source: FakeTimerSource = new FakeTimerSource();
      const ticker: AlignedTicker = new AlignedTicker(source);
      let secondCalled: boolean = false;

      // 一个条目算码失败不能拖垮其它条目：异常就地吞掉，后续订阅者照常收到通知
      ticker.subscribe(() => {
        throw new Error('boom');
      });
      ticker.subscribe(() => {
        secondCalled = true;
      });

      ticker.start();

      expect(secondCalled).assertTrue();
    });
  });
}
