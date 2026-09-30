import { IItem, IItemConfig } from '../types/Item';
import { AppStorageV2 } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPagesName, LogDomain } from '../App';
import { Toast } from '../utils/PromptAction';
import { Totp } from '../api/Totp';
import { TotpCode } from '../utils/TotpCode';

// 服务端未返回周期/进度时的兜底值（秒）
export const DEFAULT_PERIOD: number = 30;

@ObservedV2
export class ItemRuntime {
  constructor(item: IItem | ItemRuntime) {
    this._id = item.id;
    this._code = item.code;
    this._issuer = item.issuer;
    this._username = item.username;
    this._config = item.config;
  }

  static empty(): ItemRuntime {
    return new ItemRuntime({
      id: '',
      issuer: '',
      username: '',
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
  private _progress: number | undefined;

  public get progress(): number | undefined {
    return this._progress;
  }

  public set progress(value: number | undefined) {
    this._progress = value;
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

  private _config: IItemConfig;

  public get config(): IItemConfig {
    return this._config;
  }

  public set config(value: IItemConfig) {
    this._config = value;
    this._progress = value.period;
  }

  private _timeoutId: number | undefined;
  private _intervalId: number | undefined;

  // 取码序号：防止并发算码时旧结果覆盖新码
  private _computeSeq: number = 0;

  start() {
    this.stop();

    const allPathName: string[] = AppStorageV2.connect(NavPathStack)!.getAllPathName();

    if (allPathName.includes(AppPagesName.LOGIN.toString())) {
      return;
    }

    this.freshCode().catch(() => {
      // 失败已通过 Toast 提示，这里仅避免 unhandled rejection
    });

    this.schedule();
  }

  // 恢复定时器（如退后台后回前台）：重启计时并立即重算一次；端内算码代价极低，重算可吸收退后台期间的时间跃迁
  resume() {
    if (this._timeoutId !== undefined) {
      return;
    }

    const allPathName: string[] = AppStorageV2.connect(NavPathStack)!.getAllPathName();

    if (allPathName.includes(AppPagesName.LOGIN.toString())) {
      return;
    }

    this.freshCode().catch(() => {
      // 失败已通过 Toast 提示，这里仅避免 unhandled rejection
    });

    this.schedule();
  }

  stop() {
    clearTimeout(this._timeoutId)
    clearInterval(this._intervalId)

    // 保留最后一次验证码：回前台/滚回屏幕时立即可见，新验证码由页面刷新或周期到达时获取
    this._progress = undefined;
    this._timeoutId = undefined;
    this._intervalId = undefined;
  }

  // 根据更新周期对齐进度并重建定时器，周期到达时端内重算并重建定时器；
  // 倒计时必须与 TOTP 计数器同样按 epoch 秒取模，否则 period 非 60 约数（45s）或时区偏移非整小时（+05:30）时倒计时与验证码翻转错开
  private schedule() {
    if (!(this._config.period > 0)) {
      hilog.warn(LogDomain.MODELS, 'models/runtime', '非法的更新周期: %{public}d', this._config.period);

      return;
    }

    const nowSeconds = Math.floor(Date.now() / 1000);

    let progress = this._config.period - (nowSeconds % this._config.period);
    this._progress = progress;

    const intervalId = setInterval(() => {
      progress--;

      if (progress <= 0) {
        clearInterval(this._intervalId);
      }

      this._progress = progress;
    }, 1000);

    const timeoutId = setTimeout((): void => this.rotate(), Math.max(progress, 1) * 1000);

    this._timeoutId = timeoutId;
    this._intervalId = intervalId;
  }

  // 周期到点：端内重算并重建定时器（不再发起网络请求）
  private rotate() {
    this.freshCode().catch(() => {
      // 失败已通过 Toast 提示，这里仅避免 unhandled rejection
    });

    this.schedule();
  }

  async freshCode() {
    const seq = ++this._computeSeq;
    const secret = this._config.secret;

    if ('undefined' !== typeof secret && secret.length > 0) {
      try {
        const code = await TotpCode.compute(secret, this._config.period, Date.now());

        if (seq === this._computeSeq) {
          this._code = code;
        }

        return;
      } catch (e) {
        hilog.warn(LogDomain.MODELS, 'models/runtime', '端内算码失败，回退服务端: id=%{public}s', this._id);
      }
    }

    const detail =
      await Toast.execute(
        () => Totp.detail(this._id),
        undefined,
        undefined,
        $r('app.string.models_runtime_refresh_code_failed')
      );

    if (seq === this._computeSeq) {
      this._code = detail.code;
    }
  }
}

@ObservedV2
export class ItemsRuntime {
  private _runtimes: Map<string, ItemRuntime> = new Map();

  constructor(items: undefined | Array<IItem> | Iterable<IItem> = undefined) {
    if ('undefined' === typeof items) {
      return;
    }

    for (const item of Array.from(items)) {
      this.add(item);
    }
  }

  @Trace
  private _ids: string[] = [];

  get ids(): string[] {
    return this._ids;
  }

  start(id: string) {
    this._runtimes.get(id)?.start();
  }

  stop(id: string) {
    this._runtimes.get(id)?.stop();
  }

  stopAll() {
    this._ids.forEach((id: string): void => this._runtimes.get(id)?.stop());
  }

  resumeAll() {
    this._ids.forEach((id: string): void => this._runtimes.get(id)?.resume());
  }

  delete(id: string) {
    this._runtimes.get(id)?.stop();

    const index = this._ids.indexOf(id);

    if (index >= 0) {
      this._ids.splice(index, 1);
      this._ids = [...this._ids];
    }

    this._runtimes.delete(id);
  }

  get(id: string): ItemRuntime {
    return this._runtimes.get(id) ?? ItemRuntime.empty();
  }

  add(item: IItem): ItemRuntime {
    this._runtimes.get(item.id)?.stop();

    const runtime = new ItemRuntime(item);

    this._runtimes.set(item.id, runtime);

    const index = this._ids.indexOf(item.id);

    if (index >= 0) {
      this._ids.splice(index, 1);
    }

    this._ids.push(item.id);
    this._ids = [...this._ids];

    return runtime;
  }

  move(fromIndex: number, toIndex: number) {
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0 || fromIndex >= this._ids.length ||
      toIndex >= this._ids.length) {
      return;
    }

    const ids = [...this._ids];
    const movedId = ids.splice(fromIndex, 1)[0];

    if ('undefined' === typeof movedId) {
      return;
    }

    ids.splice(toIndex, 0, movedId);
    this._ids = ids;
  }

  restore(ids: string[]) {
    this._ids = [...ids];
  }

  // 以服务端数据原地刷新：顺序以服务端返回为准，更新已有条目（保留运行中的定时器）、增删差异条目
  reload(items: Iterable<IItem>) {
    const nextItems = Array.from(items);
    const nextIds = nextItems.map((item: IItem): string => item.id);

    [...this._ids]
      .filter((id: string): boolean => !nextIds.includes(id))
      .forEach((id: string): void => this.delete(id));

    nextItems.forEach((item: IItem): void => {
      const existing = this._runtimes.get(item.id);

      if (existing) {
        existing.issuer = item.issuer;
        existing.username = item.username;
        existing.config = item.config;

        // 端内算码是权威来源：仅在该条目尚无验证码时用服务端值兜底，
        // 避免用旧窗口的服务端码覆盖本地新码（周期边界竞态）
        if ('undefined' === typeof existing.code) {
          existing.code = item.code;
        }

        existing.resume();
      } else {
        this.add(item);
      }
    });

    this._ids = nextIds;
  }
}
