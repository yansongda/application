import { describe, expect, it } from '@ohos/hypium';
import {
  Clock,
  LoadingLease,
  WindowCoordinator,
  WindowLogger,
  WindowOpener,
  WindowTimings
} from '../main/ets/utils/dialog/WindowCoordinator';

const TIMINGS: WindowTimings = { closeFallbackMs: 500, openTimeoutMs: 3000, loadingWatchdogMs: 45000 };

// 假时钟：`after` 只登记不自动触发，测试里用 `flush()` 手动推进（避免真等 500ms / 45s）
class FakeClock implements Clock {
  private _seq: number = 0;
  private _tasks: Map<number, () => void> = new Map();

  after(delayMs: number, action: () => void): number {
    this._seq++;

    this._tasks.set(this._seq, action);

    return this._seq;
  }

  cancel(handle: number): void {
    this._tasks.delete(handle);
  }

  // 触发所有已登记的回调（一次性推进）
  flush(): void {
    const tasks: Array<() => void> = Array.from(this._tasks.values());

    this._tasks.clear();
    tasks.forEach((task: () => void): void => task());
  }

  get pendingCount(): number {
    return this._tasks.size;
  }
}

// 假窗口：记录开 / 关顺序；`autoDisappear` 模拟「框架在关闭时同步回调 onDidDisappear」
class FakeWindowOpener implements WindowOpener<string> {
  opened: string[] = [];
  closed: number[] = [];
  autoDisappear: boolean = true;
  hangOnOpen: boolean = false;
  private _seq: number = 0;
  private _closers: Map<number, () => void> = new Map();

  open(builder: string, onClosed: () => void): Promise<number | undefined> {
    if (this.hangOnOpen) {
      // 模拟 openCustomDialog 永不 settle（SDK 异常）
      return new Promise<number | undefined>((): void => {
      });
    }

    this._seq++;
    const id: number = this._seq;

    this.opened.push(builder);
    this._closers.set(id, onClosed);

    return Promise.resolve(id);
  }

  close(windowId: number): void {
    this.closed.push(windowId);

    const closer: (() => void) | undefined = this._closers.get(windowId);

    if (this.autoDisappear && 'undefined' !== typeof closer) {
      closer();
    }
  }

  // 手动模拟退场（`autoDisappear = false` 时用）
  disappear(windowId: number): void {
    const closer: (() => void) | undefined = this._closers.get(windowId);

    if ('undefined' !== typeof closer) {
      closer();
    }
  }
}

class RecordingLogger implements WindowLogger {
  warns: string[] = [];
  errors: string[] = [];

  warn(tag: string, message: string): void {
    this.warns.push(message);
  }

  error(tag: string, message: string): void {
    this.errors.push(message);
  }
}

class Fixture {
  opener: FakeWindowOpener = new FakeWindowOpener();
  clock: FakeClock = new FakeClock();
  log: RecordingLogger = new RecordingLogger();
  coordinator: WindowCoordinator<string>;

  constructor() {
    this.coordinator = new WindowCoordinator<string>(this.opener, this.clock, this.log, TIMINGS);
  }
}

// 让挂起的微任务跑完（协调器里的 async 链需要几轮才推进到下一步）
const drain = async (): Promise<void> => {
  for (let i = 0; i < 12; i++) {
    await Promise.resolve();
  }
};

export default function windowCoordinatorTest(): void {
  describe('windowCoordinator', () => {
    it('loading_reuses_single_window_until_all_released', 0, async () => {
      const fixture: Fixture = new Fixture();
      const first: LoadingLease = await fixture.coordinator.openLoading('a');
      const second: LoadingLease = await fixture.coordinator.openLoading('b');

      // 全局单飞：第二个调用方复用同一个窗口
      expect(fixture.opener.opened.length).assertEqual(1);
      expect(second.windowId).assertEqual(first.windowId);

      await first.release();
      // 引用未归零：窗口不能关
      expect(fixture.opener.closed.length).assertEqual(0);

      await second.release();
      expect(fixture.opener.closed.length).assertEqual(1);
    });

    it('loading_dismisses_open_alert_first', 0, async () => {
      const fixture: Fixture = new Fixture();
      const alertId: number | undefined = await fixture.coordinator.openAlert('alert');

      expect(alertId).assertEqual(1);

      const lease: LoadingLease = await fixture.coordinator.openLoading('loading');

      // 先关 alert 再开 loading（否则两个窗口同屏）
      expect(fixture.opener.opened).assertDeepEquals(['alert', 'loading']);
      expect(fixture.opener.closed).assertDeepEquals([1]);

      await lease.release();
    });

    it('stale_lease_does_not_close_next_window', 0, async () => {
      const fixture: Fixture = new Fixture();
      const stale: LoadingLease = await fixture.coordinator.openLoading('a');

      // 清场（跳登录页）：代号自增、引用归零、关掉窗口 1
      await fixture.coordinator.closeAll();
      expect(fixture.opener.closed).assertDeepEquals([1]);

      const fresh: LoadingLease = await fixture.coordinator.openLoading('b');

      // 迟到 release：那一轮的窗口已由清场关闭，不能再动新一轮的引用计数
      await stale.release();
      expect(fixture.opener.closed).assertDeepEquals([1]);

      await fresh.release();
      expect(fixture.opener.closed).assertDeepEquals([1, 2]);
    });

    it('concurrent_alerts_are_serialized', 0, async () => {
      const fixture: Fixture = new Fixture();
      const first: Promise<number | undefined> = fixture.coordinator.openAlert('a');
      const second: Promise<number | undefined> = fixture.coordinator.openAlert('b');
      const third: Promise<number | undefined> = fixture.coordinator.openAlert('c');

      await Promise.all<number | undefined>([first, second, third]);

      // 三个都开过，且每次开新的之前都关掉了旧的那个（同一时刻最多一个在屏）
      expect(fixture.opener.opened).assertDeepEquals(['a', 'b', 'c']);
      expect(fixture.opener.closed).assertDeepEquals([1, 2]);
    });

    it('open_timeout_releases_global_lock', 0, async () => {
      const fixture: Fixture = new Fixture();

      fixture.opener.hangOnOpen = true;

      const pending: Promise<LoadingLease> = fixture.coordinator.openLoading('a');

      await drain();
      fixture.clock.flush();

      const stuck: LoadingLease = await pending;

      expect(stuck.windowId).assertUndefined();
      expect(fixture.log.errors.length).assertEqual(1);

      // 关键：卡死的那次不能把后续所有弹窗一起拖死
      fixture.opener.hangOnOpen = false;

      const next: LoadingLease = await fixture.coordinator.openLoading('b');

      expect(next.windowId).assertEqual(1);
      await next.release();
    });

    it('watchdog_force_closes_leaked_loading', 0, async () => {
      const fixture: Fixture = new Fixture();

      // 故意不 release：模拟某个异常分支漏关
      await fixture.coordinator.openLoading('a');
      expect(fixture.opener.closed.length).assertEqual(0);

      // 此时时钟里只剩看门狗（打开成功的那个超时已取消）
      expect(fixture.clock.pendingCount).assertEqual(1);

      fixture.clock.flush();
      await drain();

      expect(fixture.opener.closed).assertDeepEquals([1]);
      expect(fixture.log.errors.length).assertEqual(1);
    });

    it('close_all_skips_window_already_gone', 0, async () => {
      const fixture: Fixture = new Fixture();
      const alertId: number | undefined = await fixture.coordinator.openAlert('a');

      // 框架自己关了（用户点了按钮 / 自动关框）：onDidDisappear 已触发
      fixture.opener.disappear(alertId!);
      await fixture.coordinator.closeAll();

      // 已退场的窗口不再重复 close（否则多一条 closeCustomDialog 错误日志）
      expect(fixture.opener.closed.length).assertEqual(0);
    });

    it('wait_falls_back_when_token_missing', 0, async () => {
      const fixture: Fixture = new Fixture();
      const pending: Promise<void> = fixture.coordinator.closeAndWait(99);

      await drain();

      // 令牌缺失：仍会尝试关闭一次，然后按兜底超时返回（不会永久挂住）
      expect(fixture.opener.closed).assertDeepEquals([99]);

      fixture.clock.flush();
      await pending;

      expect(fixture.log.warns.length).assertEqual(1);
    });
  });
}
