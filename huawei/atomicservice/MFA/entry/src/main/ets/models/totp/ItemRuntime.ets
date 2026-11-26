// TOTP 条目运行时：**只持有数据与算码结果**，不持定时器、不弹提示、不发请求。
//
// 与历史实现的差别（PR 重构要点）：
// - 不再有 `setInterval`/`setTimeout`/`start`/`stop`/`resume`：时间来自全局 `TotpClock`，
//   倒计时（`remaining`）是 `nowMs` 的**纯派生值**，没有「每秒本地递减的计数」可漂移；
// - 配置进模型时一次性归一化（`utils/TotpParams.ets#normalizeConfig`），下游不再兜底默认值；
// - 端内算码失败**不在这里提示、不在这里请求服务端**：返回 `RefreshOutcome.NEED_SERVER`，
//   由 `ItemsRuntime` 汇总成一次批量回退（N 条失败 = 1 个请求、1 条提示），
//   模型层因此不依赖 `Toast` / `api/*`，可以直接单测。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TOTP } from '@yansongda/otp';
import { LogDomain } from '../../App';
import { IItem, IItemConfig, NormConfig } from '../../types/Item';
import { DEFAULT_PERIOD, normalizeConfig } from '../../utils/TotpParams';
import { remainingOf, stepOf } from '../../utils/TotpProgress';
import { TotpClock } from './TotpClock';

const TAG: string = 'models/runtime';

// `refreshIfNeeded` 的结论
export enum RefreshOutcome {
  // 仍在同一时间窗内，无需动作（含「已尝试过但失败」，避免每秒重试）
  UNCHANGED,
  // 端内算码成功
  LOCAL,
  // 端内不可算（无 secret / 算码异常）：需服务端兜底
  NEED_SERVER,
}

@ObservedV2
export class ItemRuntime {
  constructor(item: IItem | ItemRuntime) {
    this._id = item.id;
    this._code = item.code;
    this._issuer = item.issuer;
    this._username = item.username;
    this._tags = item.tags ? [...item.tags] : [];
    this._pinned = item.pinned === true;
    this._config = normalizeConfig(item.config);
  }

  // 「无数据」占位实例（id 为空）：供 `@Param` 默认值与 `ItemsRuntime#get` 未命中时使用，
  // 让 UI 不必到处写 `runtime?.xxx`。调用方可用 `id.length === 0` 识别占位实例。
  static empty(): ItemRuntime {
    return new ItemRuntime({
      id: '',
      issuer: '',
      username: '',
      tags: [],
      pinned: false,
      code: '',
      config: { period: DEFAULT_PERIOD }
    });
  }

  private _id: string;

  public get id(): string {
    return this._id;
  }

  public set id(value: string) {
    this._id = value;
  }

  @Trace
  private _code: string | undefined;

  public get code(): string | undefined {
    return this._code;
  }

  public set code(value: string | undefined) {
    this._code = value;
  }

  @Trace
  private _issuer: string;

  public get issuer(): string {
    return this._issuer;
  }

  public set issuer(value: string) {
    this._issuer = value;
  }

  @Trace
  private _username: string;

  public get username(): string {
    return this._username;
  }

  public set username(value: string) {
    this._username = value;
  }

  // 标签/置顶：当前 UI 只支持单标签，数组结构为后续多标签预留
  @Trace
  private _tags: string[] = [];

  public get tags(): string[] {
    return this._tags;
  }

  public set tags(value: string[]) {
    this._tags = [...value];
  }

  // 卡片右上角展示用：当前取第一个标签
  public get tag(): string {
    return this._tags.length > 0 ? this._tags[0] : '';
  }

  @Trace
  private _pinned: boolean = false;

  public get pinned(): boolean {
    return this._pinned;
  }

  public set pinned(value: boolean) {
    this._pinned = value;
  }

  private _config: NormConfig = normalizeConfig(undefined);

  // 归一化配置：period / digits / algorithm 全部确定值，UI 直接读，不需要兜底
  public get config(): NormConfig {
    return this._config;
  }

  public set config(value: IItemConfig) {
    const next: NormConfig = normalizeConfig(value);
    const periodChanged: boolean = next.period !== this._config.period;
    const secretChanged: boolean = next.secret !== this._config.secret;

    this._config = next;

    // 周期或密钥变了，当前验证码与「已尝试 / 已兜底」的窗口全部作废，下一次 tick 立即重算。
    // 数据没变时**不得**改动其它状态：`ItemsRuntime#reload` 每次下拉刷新都会写 config，
    // 历史实现无条件 `progress = period` 会让进度条每次回到满格。
    if (periodChanged || secretChanged) {
      this._attemptedStep = -1;
      this._requestedStep = -1;
      this._codeStep = -1;
    }
  }

  public get period(): number {
    return this._config.period;
  }

  // 当前窗口剩余整秒 ∈ [1, period]：**纯派生**自全局时钟，每秒随 nowMs 自动刷新。
  // 不变量：这里只能读状态，不能写状态、不能算码（否则与 @Computed/派生语义冲突）。
  public get remaining(): number {
    return remainingOf(TotpClock.instance().nowMs, this._config.period);
  }

  // 当前时间窗序号（供调试 / 单测；UI 不用）
  public get step(): number {
    return stepOf(TotpClock.instance().nowMs, this._config.period);
  }

  // 最近一次「尝试过端内算码」的窗口序号
  private _attemptedStep: number = -1;

  // 最近一次「已发起服务端兜底」的窗口序号：同一窗口最多请求一次（否则每秒一个请求）
  private _requestedStep: number = -1;

  // 当前 `_code` 所属的窗口序号（-1 表示无可用验证码 / 属于旧窗口）
  private _codeStep: number = -1;

  // 时间窗推进到新的一格时端内重算；调用方（ItemsRuntime#onTick）负责汇总 NEED_SERVER
  refreshIfNeeded(nowMs: number): RefreshOutcome {
    const step: number = stepOf(nowMs, this._config.period);
    let computed: boolean = false;

    if (step !== this._attemptedStep) {
      this._attemptedStep = step;
      computed = this.computeLocal(nowMs);

      if (computed) {
        this._codeStep = step;

        return RefreshOutcome.LOCAL;
      }
    }

    // 本窗口仍没有可用验证码（无 secret / 算码抛错 / 首次加载）：每个窗口最多兜底一次
    if (this._codeStep !== step && this._requestedStep !== step) {
      this._requestedStep = step;

      return RefreshOutcome.NEED_SERVER;
    }

    return RefreshOutcome.UNCHANGED;
  }

  // 服务端兜底结果落地：只在「请求发出时那一格仍是当前格、且确实是本条目尝试过的那一格」时采用，
  // 避免慢请求返回的旧窗口验证码覆盖本地刚算出的新码（周期边界竞态）
  applyServerCode(code: string, issuedAtMs: number): void {
    const step: number = stepOf(issuedAtMs, this._config.period);

    if (step !== this._attemptedStep) {
      return;
    }

    if (step !== stepOf(TotpClock.instance().nowMs, this._config.period)) {
      return;
    }

    this._code = code;
    this._codeStep = step;
  }

  // 服务端数据兜底（列表刷新 / 新增条目时用）：仅当**当前窗口**还没有验证码时采用，
  // 端内算出的码是权威来源，不被服务端旧窗口的码覆盖
  applyServerCodeForCurrentWindow(code: string | undefined): void {
    if ('undefined' === typeof code || code.length <= 0) {
      return;
    }

    const step: number = stepOf(TotpClock.instance().nowMs, this._config.period);

    if (this._codeStep === step) {
      return;
    }

    this._code = code;
    this._codeStep = step;
  }

  // 端内算码（唯一调用点：refreshIfNeeded）。成功返回 true 并已写入 `_code`
  private computeLocal(nowMs: number): boolean {
    const secret: string | undefined = this._config.secret;

    if ('undefined' === typeof secret || secret.length <= 0) {
      return false;
    }

    try {
      // 显式传 nowMs：保证「算哪一格」与本 tick 的 remaining 完全一致，
      // 不依赖 generate 内部再取一次 Date.now()（周期边界处会算出上一格）
      this._code = new TOTP({
        secret: secret,
        period: this._config.period,
        digits: this._config.digits,
        algorithm: this._config.algorithm,
      }).generate(nowMs);

      return true;
    } catch (e) {
      hilog.warn(LogDomain.MODELS, TAG, '端内算码失败，转服务端兜底: id=%{public}s', this._id);

      return false;
    }
  }
}
