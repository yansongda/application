import { HashMap } from '@kit.ArkTS';
import { IItem, IItemConfig } from '../types/Item';
import { AppStorageV2 } from '@kit.ArkUI';
import { AppPagesName } from '../App';
import { Toast } from '../utils/PromptAction';
import { Totp } from '../api/Totp';

@ObservedV2
export class ItemRuntime {
  constructor(item: IItem | ItemRuntime) {
    this._id = item.id;
    this._code = item.code;
    this._issuer = item.issuer;
    this._username = item.username;
    this._config = item.config;
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

  public get timeoutId(): number | undefined {
    return this._timeoutId;
  }

  public set timeoutId(value: number | undefined) {
    this._timeoutId = value;
  }

  private _intervalId: number | undefined;

  public get intervalId(): number | undefined {
    return this._intervalId;
  }

  public set intervalId(value: number | undefined) {
    this._intervalId = value;
  }

  start() {
    this.stop();

    const allPathName: string[] = AppStorageV2.connect(NavPathStack)!.getAllPathName();

    if (AppPagesName.LOGIN.toString() === (allPathName[0] ?? 'undefined')) {
      return;
    }

    this.freshCode();

    const now = new Date();

    let progress = this._config.period - (now.getSeconds() % this._config.period);
    this._progress = progress;

    const intervalId = setInterval(() => {
      progress--;

      if (progress <= 0) {
        clearInterval(this._intervalId);
      }

      this._progress = progress;
    }, 1000);

    const timeoutId = setTimeout((): void => this.start(), Math.max(progress, 1) * 1000);

    this._timeoutId = timeoutId;
    this._intervalId = intervalId;
  }

  stop() {
    clearTimeout(this._timeoutId)
    clearInterval(this._intervalId)

    this._code = undefined;
    this._progress = undefined;
    this._timeoutId = undefined;
    this._intervalId = undefined;
  }

  async freshCode() {
    const detail =
      await Toast.execute(
        () => Totp.detail(this._id),
        undefined,
        undefined,
        $r('app.string.models_runtime_refresh_code_failed')
      );

    this._code = detail.code;
  }
}

@ObservedV2
export class ItemsRuntime {
  private _runtimes: HashMap<string, ItemRuntime> = new HashMap();

  constructor(items: undefined | Array<IItem> | Iterable<IItem> = undefined) {
    if ('undefined' === typeof items) {
      return;
    }

    try {
      this._runtimes.clear();
    } catch (error) {
    }

    for (const item of Array.from(items).sort((a: IItem, b: IItem): number => b.sort - a.sort)) {
      this.add(item);
    }
  }

  @Trace
  private _ids: string[] = [];

  get ids(): string[] {
    return this._ids;
  }

  start(id: string) {
    this.get(id).start();
  }

  stop(id: string) {
    this.get(id).stop();
  }

  delete(id: string) {
    this.stop(id);

    const index = this._ids.indexOf(id);

    if (index >= 0) {
      this._ids.splice(index, 1);
      this._ids = [...this._ids];
    }

    try {
      this._runtimes.remove(id);
    } catch (error) {
    }
  }

  get(id: string): ItemRuntime {
    let runtime: undefined | ItemRuntime = undefined;

    try {
      runtime = this._runtimes.get(id);
    } catch (error) {
    }

    return runtime ?? new ItemRuntime({} as IItem);
  }

  isEmpty(): boolean {
    return this._ids.length === 0;
  }

  clear() {
    [...this._ids].forEach((id: string): void => this.delete(id));
  }

  add(item: IItem): ItemRuntime {
    this.stop(item.id);

    const runtime = new ItemRuntime(item);

    try {
      this._runtimes.set(item.id, runtime);

      const index = this._ids.indexOf(item.id);

      if (index >= 0) {
        this._ids.splice(index, 1);
      }

      this._ids.push(item.id);
      this._ids = [...this._ids];
    } catch (error) {
    }

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
}
