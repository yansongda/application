// TOTP 条目集合运行时：id 顺序（@Trace，供列表 Repeat 使用）+ 条目运行时映射。
import { IItem } from '../../types/Item';
import { ItemRuntime } from './ItemRuntime';

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
