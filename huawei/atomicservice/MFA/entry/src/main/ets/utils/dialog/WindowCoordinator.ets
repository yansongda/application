// 弹窗窗口协调器（纯逻辑）：所有「该不该开 / 该不该关 / 要不要等退场」的并发决策都在这里。
//
// 为什么单独抽出这一层：窗口层是这段代码里最容易出错的部分（单飞、引用计数、打开代号、迟到关闭、
// 看门狗），而这些决策与 ArkUI 调用没有关系。把 ArkUI 调用（`WindowOpener`）和定时器（`Clock`）
// 注入进来后，`entry/src/test` 里可以用假实现把每个边界都跑一遍（见 `WindowCoordinator.test.ets`）。
//
// 术语：
// - 槽位（slot）：全局只有两个——loading（可被多处方共享）与 alert（单槽位重试/失败框）；
// - 租约（lease）：每次 openLoading 发一张，`release` 只释放自己这张。清场（closeAll）之后迟到的
//   release 因为代号不匹配不会再动新一轮的计数——这是「一个全局引用计数」无法表达的信息；
// - 令牌（token）：窗口 id → 是否已退场。`closeCustomDialog(id)` 是同步 void，真实退场只能靠
//   `onDidDisappear`；令牌在回调里只标记 closed、不删除（框架自动关框后槽位仍指向该 id，
//   删了会让下一次 closeAndWait 白等兜底超时并对已不存在的 id 再关一次）。
import { errorMessage } from '../Errors';

const TAG: string = 'utils/dialog';

export interface WindowOpener<B> {
  // 打开一个窗口并返回窗口 id（失败返回 undefined）；
  // `onClosed` 必须在窗口**真正退场**时被调用（由实现方接到 `onDidDisappear` 上）
  open(builder: B, onClosed: () => void): Promise<number | undefined>;
  // 关闭指定窗口（同步 void，真实的退场时间未知）
  close(windowId: number): void;
}

export interface Clock {
  // delayMs 后执行 action，返回可取消的句柄
  after(delayMs: number, action: () => void): number;
  cancel(handle: number): void;
}

export interface WindowLogger {
  warn(tag: string, message: string): void;
  error(tag: string, message: string): void;
}

export interface WindowTimings {
  // 等 onDidDisappear 的兜底：系统异常 / 回调缺失（关弹窗同时页面切换导致退场动画被打断时
  // SDK 明确不会回调）时最多等这么久
  closeFallbackMs: number;
  // 打开兜底：`openCustomDialog` 一旦不 settle，窗口层的全局锁会永久卡住，之后整个 App 开不出弹窗
  openTimeoutMs: number;
  // loading 看门狗：任何异常分支漏关时兜底，避免 autoCancel 为 false 的遮罩永久挡住页面
  // （必须大于最长请求超时，否则会误杀进行中的请求）
  loadingWatchdogMs: number;
}

// loading 租约：调用方必须 `release()`，否则窗口要等看门狗才会被强制关闭
export interface LoadingLease {
  // 打开后的窗口 id（复用已有窗口 / 打开被取消时为 undefined）
  readonly windowId: number | undefined;
  readonly release: () => Promise<void>;
}

interface ClosedToken {
  closed: boolean;
  waiters: Array<() => void>;
}

export class WindowCoordinator<B> {
  private readonly _opener: WindowOpener<B>;
  private readonly _clock: Clock;
  private readonly _log: WindowLogger;
  private readonly _timings: WindowTimings;

  // 窗口 id → 是否已退场
  private _tokens: Map<number, ClosedToken> = new Map();

  // loading 槽位
  private _loadingId: number | undefined = undefined;
  private _leases: number = 0;
  private _opening: Promise<number | undefined> | undefined = undefined;
  private _gen: number = 0;
  private _watchdog: number | undefined = undefined;

  // alert 槽位
  private _alertId: number | undefined = undefined;
  private _alertOpening: Promise<number | undefined> | undefined = undefined;
  private _alertGen: number = 0;

  constructor(opener: WindowOpener<B>, clock: Clock, log: WindowLogger, timings: WindowTimings) {
    this._opener = opener;
    this._clock = clock;
    this._log = log;
    this._timings = timings;
  }

  // 打开（或复用）全局单飞 loading
  async openLoading(builder: B): Promise<LoadingLease> {
    const gen: number = this._gen;

    this._leases++;

    // 串行化：上一个 open 还在飞（含被清场取消、正在自行关窗的那次）就先等它落地再判断
    await this.settleOpening();

    if ('undefined' !== typeof this._loadingId) {
      return this.lease(gen, this._loadingId);
    }

    const opening: Promise<number | undefined> = (async (): Promise<number | undefined> => {
      // 重试框按钮的同步 action 会立刻开 loading：先关掉上一个 alert 并等它真正退场，
      // 避免两个窗口同屏（这一步取代了各页面各自的 setTimeout(200)）
      await this.dismissAlertAndWait();

      // 等待期间可能发生清场（跳登录页）或调用方已全部释放。此时不要再开窗，
      // 否则窗口会先真的显示出来、再因代号不匹配被关掉，表现为「登录页上闪一下 loading」
      if (gen !== this._gen || this._leases <= 0) {
        return undefined;
      }

      const id: number | undefined = await this.openWindow(builder);

      if ('undefined' === typeof id) {
        return undefined;
      }

      if (gen !== this._gen || this._leases <= 0) {
        // 打开期间发生了清场 / 调用方已全部释放（请求秒回）：立刻关掉，别留给看门狗
        await this.closeAndWait(id);

        return undefined;
      }

      this._loadingId = id;
      this.startWatchdog(id);

      return id;
    })();

    this._opening = opening;

    try {
      return this.lease(gen, await opening);
    } finally {
      if (this._opening === opening) {
        this._opening = undefined;
      }
    }
  }

  // 打开重试 / 失败框（单槽位）：并发调用排队，先关旧框再开新框
  async openAlert(builder: B): Promise<number | undefined> {
    await this.settleAlertOpening();

    const gen: number = this._alertGen;
    const opening: Promise<number | undefined> = (async (): Promise<number | undefined> => {
      const previous: number | undefined = this._alertId;

      this._alertId = undefined;

      if ('undefined' !== typeof previous) {
        // 等旧框真正退场，避免新旧两个 alert 同屏
        await this.closeAndWait(previous);
      }

      // 等旧框期间可能发生了清场：不要再开新窗（同 openLoading 的说明）
      if (gen !== this._alertGen) {
        return undefined;
      }

      const id: number | undefined = await this.openWindow(builder);

      if ('undefined' === typeof id) {
        return undefined;
      }

      if (gen !== this._alertGen) {
        await this.closeAndWait(id);

        return undefined;
      }

      this._alertId = id;

      return id;
    })();

    this._alertOpening = opening;

    try {
      return await opening;
    } finally {
      if (this._alertOpening === opening) {
        this._alertOpening = undefined;
      }
    }
  }

  // 强制清场并等待全部退场（跳登录页前使用）
  async closeAll(): Promise<void> {
    const loadingId: number | undefined = this.resetLoading();
    const alertId: number | undefined = this.resetAlert();

    // 两个窗口互不依赖：并行等待，避免串行的两个兜底超时叠加成两倍延迟
    await Promise.all<void>([this.closeAndWait(loadingId), this.closeAndWait(alertId)]);
  }

  // 打开 loading 前调用：关掉当前 alert 并等它真正退场，替代页面里的 setTimeout 延迟。
  // 必须**主动关闭**而不是只等待：alert 可能仍在等用户操作（此时它并没有在退场），只等待会让槽位
  // 提前清空、窗口却留在屏幕上，`closeAll()` 之后也再关不掉它（孤儿窗口）。
  // 用「读并清空槽位」而不是 reset：reset 会自增代号，把正在打开中的重试框一并取消掉。
  private async dismissAlertAndWait(): Promise<void> {
    const id: number | undefined = this._alertId;

    this._alertId = undefined;

    if ('undefined' === typeof id) {
      return;
    }

    await this.closeAndWait(id);
  }

  // 关窗并等待真实退场（onDidDisappear）；拿不到令牌时按兜底超时返回。
  // 对外可见仅为了可测性（`WindowCoordinator.test.ets` 覆盖「令牌缺失」这条防御路径），业务代码只用上面的槽位 API。
  async closeAndWait(windowId: number | undefined): Promise<void> {
    if ('undefined' === typeof windowId) {
      return;
    }

    const token: ClosedToken | undefined = this._tokens.get(windowId);

    // 窗口已自行退场（用户点了 alert 按钮 / 框架自动关框）：不用再关，也不用等兜底
    if ('undefined' !== typeof token && token.closed) {
      this._tokens.delete(windowId);

      return;
    }

    try {
      this._opener.close(windowId);
    } catch (e) {
      this._log.warn(TAG, '调用 `closeCustomDialog` 失败: ' + errorMessage(e));
    }

    await this.waitClosed(windowId);
  }

  private lease(gen: number, windowId: number | undefined): LoadingLease {
    return {
      windowId: windowId,
      release: (): Promise<void> => this.releaseLoading(gen),
    };
  }

  // 释放一张租约：代号不匹配说明中途发生过清场（那一轮窗口已被清场关闭），不能再动新一轮的计数
  private async releaseLoading(gen: number): Promise<void> {
    if (gen !== this._gen) {
      return;
    }

    this._leases = this._leases > 0 ? this._leases - 1 : 0;

    if (this._leases > 0) {
      return;
    }

    await this.settleOpening();

    // 等待期间（至少一个微任务）可能有新调用方拿到租约、甚至已经开了新窗口：
    // 此时不能再按「引用归零」关闭窗口，否则会误关别人的 loading
    if (this._leases > 0) {
      return;
    }

    const id: number | undefined = this._loadingId;

    this.clearWatchdog();
    this._loadingId = undefined;

    if ('undefined' === typeof id) {
      return;
    }

    await this.closeAndWait(id);
  }

  private resetLoading(): number | undefined {
    this._gen++;

    const id: number | undefined = this._loadingId;

    this._loadingId = undefined;
    this._leases = 0;
    // **不要**清 `_opening`：在飞的 open 会被代号取消并自行关窗，清掉它会让下一次 open
    // 不再等待 → 两个 loading 窗口可能同屏。与 resetAlert 保持同一语义。
    this.clearWatchdog();

    return id;
  }

  private resetAlert(): number | undefined {
    this._alertGen++;

    const id: number | undefined = this._alertId;

    this._alertId = undefined;

    return id;
  }

  // 等 loading 槽位上在飞的 open 落地（防御性清 `_opening`，避免 finally 异常时死循环）
  private async settleOpening(): Promise<void> {
    while ('undefined' !== typeof this._opening) {
      const previous: Promise<number | undefined> = this._opening;

      try {
        await previous;
      } catch (e) {
        // 打开失败：继续走下面的新建逻辑
      }

      if (this._opening === previous) {
        this._opening = undefined;
      }
    }
  }

  // 等 alert 槽位上在飞的 open 落地
  private async settleAlertOpening(): Promise<void> {
    while ('undefined' !== typeof this._alertOpening) {
      const previous: Promise<number | undefined> = this._alertOpening;

      try {
        await previous;
      } catch (e) {
        // 上一个 alert 打开失败：继续打开当前这个
      }

      if (this._alertOpening === previous) {
        this._alertOpening = undefined;
      }
    }
  }

  // 打开窗口并兜住「promise 永不 settle」：否则 `_opening` 永不清空，之后所有弹窗都会卡在串行化等待里
  private openWindow(builder: B): Promise<number | undefined> {
    return new Promise<number | undefined>((resolve: (id: number | undefined) => void): void => {
      // 令牌先建：`onDidDisappear` 没有参数，只能靠闭包认领自己的窗口
      const token: ClosedToken = { closed: false, waiters: [] };
      let settled: boolean = false;
      const timer: number = this._clock.after(this._timings.openTimeoutMs, (): void => {
        if (settled) {
          return;
        }

        settled = true;
        this._log.error(TAG, '打开弹窗超时，放弃本次窗口（避免全局锁卡死）');
        resolve(undefined);
      });

      const finish = (id: number | undefined): void => {
        if (settled) {
          // 超时之后才真正开出来的窗口没人接管：立刻关掉，别留在屏幕上
          if ('undefined' !== typeof id) {
            this.closeQuietly(id);
          }

          return;
        }

        settled = true;
        this._clock.cancel(timer);

        if ('undefined' !== typeof id) {
          this._tokens.set(id, token);
        }

        resolve(id);
      };

      this._opener.open(builder, (): void => this.markClosed(token))
        .then(finish, (e: Error): void => {
          this._log.error(TAG, '调用 `openCustomDialog` 失败: ' + errorMessage(e));
          finish(undefined);
        });
    });
  }

  // 窗口真正退场：只标记，不删令牌（见文件头说明）
  private markClosed(token: ClosedToken): void {
    token.closed = true;

    const waiters: Array<() => void> = token.waiters;

    token.waiters = [];
    waiters.forEach((waiter: () => void): void => waiter());
  }

  private async waitClosed(windowId: number): Promise<void> {
    const token: ClosedToken | undefined = this._tokens.get(windowId);

    if ('undefined' === typeof token) {
      // 令牌缺失：窗口可能在登记前就被清场。作为「令牌表清理漏了」的探针，日志里留一条 warn
      this._log.warn(TAG, '等待窗口退场时找不到令牌，按兜底超时返回: id=' + windowId.toString());

      await this.waitFallback();
      return;
    }

    if (token.closed) {
      this._tokens.delete(windowId);

      return;
    }

    await new Promise<void>((resolve: () => void): void => {
      const timer: number = this._clock.after(this._timings.closeFallbackMs, (): void => resolve());

      token.waiters.push((): void => {
        this._clock.cancel(timer);
        resolve();
      });
    });

    this._tokens.delete(windowId);
  }

  private waitFallback(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      this._clock.after(this._timings.closeFallbackMs, (): void => resolve());
    });
  }

  private startWatchdog(windowId: number): void {
    this.clearWatchdog();

    this._watchdog = this._clock.after(this._timings.loadingWatchdogMs, (): void => {
      this._watchdog = undefined;

      if (this._loadingId !== windowId) {
        return;
      }

      this._log.error(TAG, 'loading 超时未关闭，强制关闭: id=' + windowId.toString());

      this._loadingId = undefined;
      this._leases = 0;

      // 走 closeAndWait 顺带清掉令牌（直接 close 会留下一条永远不删的令牌）
      this.closeAndWait(windowId).catch((): void => {
        // 看门狗兜底路径不再上抛
      });
    });
  }

  private clearWatchdog(): void {
    if ('undefined' === typeof this._watchdog) {
      return;
    }

    this._clock.cancel(this._watchdog);
    this._watchdog = undefined;
  }

  private closeQuietly(windowId: number): void {
    try {
      this._opener.close(windowId);
    } catch (e) {
      this._log.warn(TAG, '调用 `closeCustomDialog` 失败: ' + errorMessage(e));
    }
  }
}
