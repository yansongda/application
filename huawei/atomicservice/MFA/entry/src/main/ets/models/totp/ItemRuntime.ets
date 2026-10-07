import { IItem, IItemConfig } from '../../types/Item';
import { AppStorageV2 } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPagesName, LogDomain } from '../../App';
import { Toast } from '../../utils/PromptAction';
import { Totp } from '../../api/Totp';
import { TOTP } from '@yansongda/otp';

// TOTP 条目运行时（端内算码 + 周期倒计时）。
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
        // 用局部 intervalId 清理自身：rotate() 可能已重建定时器并覆盖实例字段 _intervalId，引用字段会误清新定时器
        clearInterval(intervalId);
      }

      this._progress = progress;
    }, 1000);

    const timeoutId = setTimeout((): void => this.rotate(), Math.max(progress, 1) * 1000);

    this._timeoutId = timeoutId;
    this._intervalId = intervalId;
  }

  // 周期到点：端内重算并重建定时器（以端内算码为主，secret 缺失/算码失败时回退服务端 detail）
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
        const code: string = new TOTP({ secret: secret, period: this._config.period }).generate();

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
