import { Type } from '@kit.ArkUI';

// 接口返回的是普通 JSON（不是被观测的类实例），因此对外只承诺这些字段
export interface IUserConfig {
  avatar?: string | null;
  nickname?: string | null;
  slogan?: string | null;
}

export interface IUser {
  phone?: string | null;
  config?: IUserConfig | null;
}

// 空值归一：接口/持久化可能给出 null，统一转成 undefined，保持与类型声明一致（用 ?? / typeof 判断都不会再漏）
function normalizeText(value: string | null | undefined): string | undefined {
  return 'undefined' === typeof value || null === value ? undefined : value;
}

@ObservedV2
export class Config {
  @Trace
  private _avatar: string | undefined;

  public get avatar(): string | undefined {
    return this._avatar;
  }

  public set avatar(value: string | null | undefined) {
    this._avatar = normalizeText(value);
  }

  @Trace
  private _nickname: string | undefined;

  public get nickname(): string | undefined {
    return this._nickname;
  }

  public set nickname(value: string | null | undefined) {
    this._nickname = normalizeText(value);
  }

  @Trace
  private _slogan: string | undefined;

  public get slogan(): string | undefined {
    return this._slogan;
  }

  public set slogan(value: string | null | undefined) {
    this._slogan = normalizeText(value);
  }

  // 原地更新：逐字段赋值会触发 @Trace 刷新，整体替换对象则不会
  update(source: IUserConfig): void {
    this.avatar = source.avatar;
    this.nickname = source.nickname;
    this.slogan = source.slogan;
  }
}

@ObservedV2
export class User {
  constructor() {
    this._config = new Config();
  }

  @Trace
  private _phone: string | undefined;

  public get phone(): string | undefined {
    return this._phone;
  }

  public set phone(value: string | null | undefined) {
    this._phone = normalizeText(value);
  }

  @Type(Config)
  @Trace
  private _config: Config;

  public get config(): Config {
    return this._config;
  }

  public set config(value: Config) {
    this._config = value;
  }

  // 用接口返回的数据原地更新。
  // 注意：不能写成 `this.config = source.config` —— 接口返回的是普通 JSON 对象，
  // 那样会把被观测的 Config 实例替换成普通对象，之后 user.config.xxx 的修改将不会触发 UI 刷新
  // （表现为：后端已更新成功，页面仍显示旧值，重启应用才正常）。
  apply(source: IUser): void {
    this.phone = source.phone;
    this.config.update(source.config ?? {});
  }
}
