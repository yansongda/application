// TOTP 条目集合运行时：id 顺序（@Trace，供列表 Repeat 使用）+ 条目运行时映射 + **全应用唯一**的算码驱动。
//
// 分层（与本目录其它模型一致）：
// - 时间：`models/totp/TotpClock.ets`（唯一秒级定时器）；
// - 算码：本类每 tick 遍历条目，让到期的条目端内重算（`ItemRuntime#refreshIfNeeded`）；
// - 兜底：本端算不了（无 secret / 算码异常）的条目在**同一 tick 内汇总**，只发一次 `/totp/all`，
//   避免历史实现「每条目各发一次 /totp/detail」的 N 倍请求与 N 条失败提示；
// - 提示：本类不 import 任何 UI 模块，失败经 `onError` 回调交给页面（由 `pages/index/Index.ets` 接线）。
//
// 注意：本类**不再**提供 start/stop/resume —— 起停只有一个入口（`TotpClock.attach/detach`，
// 由 EntryAbility 的前后台回调驱动）。页面切换不参与计时，因此不会出现「详情页压住列表时表停了」。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../../App';
import { Totp } from '../../api/Totp';
import { IItem } from '../../types/Item';
import { AuthExpiredError, toError } from '../../utils/Errors';
import { ItemView } from '../../utils/ItemFilter';
import { loginInStack } from '../../utils/NavState';
import { SingleFlight } from '../../utils/SingleFlight';
import { ItemRuntime, RefreshOutcome } from './ItemRuntime';
import { TotpClock } from './TotpClock';

const TAG: string = 'models/items_runtime';
// 兜底失败提示的最小间隔：断网时每 30s 一次的验证码周期不该变成每 30s 一次的气泡
const FAILURE_NOTIFY_INTERVAL_MS: number = 60000;

@ObservedV2
export class ItemsRuntime {
  private _runtimes: Map<string, ItemRuntime> = new Map();
  // 服务端兜底单飞：同一波需要的条目共享一次请求
  private _fallback: SingleFlight<IItem[]> = new SingleFlight<IItem[]>();
  // 当前在飞兜底请求的发起时刻：迟到返回时据此判断「是否还是同一时间窗」
  private _fallbackIssuedAt: number = 0;
  private _lastErrorAt: number = 0;

  constructor(items: undefined | Array<IItem> | Iterable<IItem> = undefined) {
    if ('undefined' === typeof items) {
      return;
    }

    for (const item of Array.from(items)) {
      this.add(item);
    }
  }

  // 失败提示的出口：由页面接线（模型不 import Toast；也保证同一波失败只提示一次）
  onError: (message: ResourceStr) => void = () => {
  };

  @Trace
  private _ids: string[] = [];

  get ids(): string[] {
    return this._ids;
  }

  // 每秒驱动一次（由 EntryAbility 把 TotpClock 与本方法接线）：
  // 只有「时间窗变了」的条目才会真正重算，因此这里每秒的成本是一次整数除法比较。
  onTick(nowMs: number): void {
    // 登录页在栈中说明正在重新认证：不要算码、也不要发兜底请求（会在登录页背后空转）
    if (loginInStack() || this._ids.length <= 0) {
      return;
    }

    const needServer: ItemRuntime[] = [];
    let localOk: boolean = false;

    for (const id of this._ids) {
      const runtime: ItemRuntime | undefined = this._runtimes.get(id);

      if ('undefined' === typeof runtime) {
        continue;
      }

      const outcome: RefreshOutcome = runtime.refreshIfNeeded(nowMs);

      if (RefreshOutcome.NEED_SERVER === outcome) {
        needServer.push(runtime);
      } else if (RefreshOutcome.LOCAL === outcome) {
        localOk = true;
      }
    }

    if (localOk) {
      // 端内算码恢复后重置提示节流，下次真失败还能立刻提示
      this._lastErrorAt = 0;
    }

    if (needServer.length > 0) {
      this.fallbackFromServer(needServer, nowMs);
    }
  }

  delete(id: string): void {
    this._runtimes.delete(id);
    this._ids = this._ids.filter((current: string): boolean => current !== id);
  }

  // 「无数据」占位实例（id 为空）：列表项 / 详情页据此渲染空态，不必到处判空
  get(id: string): ItemRuntime {
    return this._runtimes.get(id) ?? ItemRuntime.empty();
  }

  add(item: IItem): ItemRuntime {
    const runtime = new ItemRuntime(item);

    this._runtimes.set(item.id, runtime);
    this._ids = this._ids.filter((current: string): boolean => current !== item.id).concat(item.id);

    // 新增即算码：不能只等下一次 tick，否则新条目最多白 1 秒。
    // 端内算不了（无 secret）时用创建接口返回的验证码兜底；连这个都没有才发请求。
    const nowMs: number = TotpClock.instance().nowMs;

    runtime.applyServerCodeForCurrentWindow(item.code);

    if (RefreshOutcome.NEED_SERVER === runtime.refreshIfNeeded(nowMs)) {
      this.fallbackFromServer([runtime], nowMs);
    }

    return runtime;
  }

  move(fromIndex: number, toIndex: number): void {
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0 || fromIndex >= this._ids.length ||
      toIndex >= this._ids.length) {
      return;
    }

    const ids: string[] = [...this._ids];
    const moved: string[] = ids.splice(fromIndex, 1);

    if (moved.length <= 0) {
      return;
    }

    ids.splice(toIndex, 0, moved[0]);
    this._ids = ids;
  }

  restore(ids: string[]): void {
    this._ids = [...ids];
  }

  // 供搜索/筛选/分组纯函数使用：按当前 id 顺序导出轻量视图，不复制定时器与配置
  snapshot(): ItemView[] {
    const items: ItemView[] = [];

    for (const id of this._ids) {
      const runtime: ItemRuntime | undefined = this._runtimes.get(id);

      if ('undefined' === typeof runtime) {
        continue;
      }

      items.push({
        id: runtime.id,
        issuer: runtime.issuer,
        username: runtime.username,
        tags: runtime.tags,
        pinned: runtime.pinned,
      });
    }

    return items;
  }

  // 以服务端数据原地刷新：顺序以服务端返回为准，更新已有条目（保留本窗口的验证码）、增删差异条目
  reload(items: Iterable<IItem>): void {
    const nextItems: IItem[] = Array.from(items);
    const nextIds: string[] = nextItems.map((item: IItem): string => item.id);
    const nowMs: number = TotpClock.instance().nowMs;
    const needServer: ItemRuntime[] = [];

    this._ids
      .filter((id: string): boolean => !nextIds.includes(id))
      .forEach((id: string): void => this.delete(id));

    nextItems.forEach((item: IItem): void => {
      const existing: ItemRuntime | undefined = this._runtimes.get(item.id);

      if ('undefined' === typeof existing) {
        this.add(item);

        return;
      }

      existing.issuer = item.issuer;
      existing.username = item.username;
      existing.tags = item.tags ?? [];
      existing.pinned = item.pinned === true;
      // config 的 setter 只在周期 / 密钥真变了时作废验证码，普通刷新不会打断倒计时
      existing.config = item.config;
      // 端内算码是权威来源：仅当**当前窗口**还没有验证码时才用服务端值兜底，
      // 避免用旧窗口的服务端码覆盖本地新码（周期边界竞态）
      existing.applyServerCodeForCurrentWindow(item.code);

      if (RefreshOutcome.NEED_SERVER === existing.refreshIfNeeded(nowMs)) {
        needServer.push(existing);
      }
    });

    this._ids = nextIds;

    if (needServer.length > 0) {
      this.fallbackFromServer(needServer, nowMs);
    }
  }

  // 注销账号 / 清空本地数据：运行时持有**明文 secret**，必须显式清空，
  // 否则旧账号的密钥会一直驻留到进程退出（换账号登录后还会被继续算码）。
  clearAll(): void {
    hilog.info(LogDomain.MODELS, TAG, 'clear_all: count=%{public}d', this._runtimes.size);

    this._runtimes.clear();
    this._ids = [];
    this._lastErrorAt = 0;
  }

  // 兜底：同一 tick 内需要的条目共用一次 `/totp/all`（单飞），失败只提示一次
  private fallbackFromServer(targets: ItemRuntime[], issuedAtMs: number): void {
    this._fallback.run((): Promise<IItem[]> => {
      // 记录本次请求的发起时刻（单飞期间的后来者不会改写它）：
      // 迟到返回时据此判断「是否还是同一时间窗」，避免把上一格的验证码当本格用
      this._fallbackIssuedAt = issuedAtMs;
      hilog.info(LogDomain.MODELS, TAG, 'fallback: count=%{public}d', targets.length);

      return Totp.all();
    }).then((items: IItem[]): void => {
      const codes: Map<string, string> = new Map();

      for (const item of items) {
        codes.set(item.id, item.code);
      }

      for (const target of targets) {
        const code: string | undefined = codes.get(target.id);

        if ('undefined' !== typeof code) {
          // 内部会校验「请求发出时那一格仍是当前格」，过期结果直接丢弃
          target.applyServerCode(code, this._fallbackIssuedAt);
        }
      }
    }).catch((caught: Error): void => {
      const error: Error = toError(caught);

      // 认证失效已由 SessionGuard 跳登录页：再弹提示只会叠在登录页上方
      if (error instanceof AuthExpiredError) {
        return;
      }

      hilog.warn(LogDomain.MODELS, TAG, 'fallback_failed: %{public}s', JSON.stringify(error));
      this.reportFailure(issuedAtMs);
    });
  }

  // 失败提示节流：断网时验证码周期 30s，不该每 30s 弹一次气泡
  private reportFailure(nowMs: number): void {
    if (nowMs - this._lastErrorAt < FAILURE_NOTIFY_INTERVAL_MS) {
      return;
    }

    this._lastErrorAt = nowMs;

    if (loginInStack()) {
      return;
    }

    this.onError($r('app.string.models_runtime_refresh_code_failed'));
  }
}
