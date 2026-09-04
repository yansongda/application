import { authentication } from '@kit.AccountKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { App, LogDomain } from '../App';
import { dateformat } from '@developers/dateformat';
import { AccessToken } from '../api/AccessToken';
import { Context } from '@kit.AbilityKit';

export enum State {
  EMPTY_AUTHORIZATION = 0,

  NEED_REFRESH = 1,

  REFRESH_TOKEN_EXPIRED = 2,

  NORMAL = 3,
}

@ObservedV2
export class Authorization {
  @Trace
  private _authorizedAt: Date | undefined;

  public get authorizedAt(): Date | undefined {
    return this._authorizedAt;
  }

  @Trace
  private _accessToken: string | undefined;

  public get accessToken(): string | undefined {
    return this._accessToken;
  }

  @Trace
  private _refreshToken: string | undefined;

  public get refreshToken(): string | undefined {
    return this._refreshToken;
  }

  @Trace
  private _expiredAt: Date | undefined;

  public get expiredAt(): Date | undefined {
    return this._expiredAt;
  }

  static async authenticateWithHuaweiID(scopes?: string[], context?: Context): Promise<authentication.AuthorizationWithHuaweiIDCredential> {
    const request =
      new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest();

    request.scopes = scopes;
    request.forceAuthorization = true;
    request.supportAtomicService = true;
    request.state = util.generateRandomUUID();

    let authenticateWithHuaweiIDResponse: authentication.AuthorizationWithHuaweiIDResponse;

    try {
      authenticateWithHuaweiIDResponse =
        await (new authentication.AuthenticationController(context)).executeRequest(request);
    } catch (error) {
      // 对于元服务来说，不太可能出现异常，因为元服务必须是登录状态。
      hilog.error(LogDomain.MODELS, 'models/auth', '元服务登录出错: %{public}s', JSON.stringify(error))

      return Promise.reject();
    }

    if (authenticateWithHuaweiIDResponse.state && request.state !== authenticateWithHuaweiIDResponse.state) {
      hilog.error(LogDomain.MODELS, 'models/auth', '登录失败，state 不同: %{public}s != %{public}s',
        authenticateWithHuaweiIDResponse.state, request.state);

      return Promise.reject();
    }

    return authenticateWithHuaweiIDResponse.data!;
  }

  static async loginWithHuaweiID(): Promise<authentication.LoginWithHuaweiIDCredential> {
    const request = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();

    request.forceLogin = false;
    request.state = util.generateRandomUUID();

    let loginWithHuaweiIDResponse: authentication.LoginWithHuaweiIDResponse;

    try {
      loginWithHuaweiIDResponse =
        await (new authentication.AuthenticationController()).executeRequest(request);
    } catch (error) {
      // 对于元服务来说，不太可能出现异常，因为元服务必须是登录状态。
      hilog.error(LogDomain.MODELS, 'models/auth', '元服务登录出错: %{public}s', JSON.stringify(error))

      return Promise.reject();
    }

    if (loginWithHuaweiIDResponse.state && request.state !== loginWithHuaweiIDResponse.state) {
      hilog.error(LogDomain.MODELS, 'models/auth', '登录失败，state 不同: %{public}s != %{public}s',
        loginWithHuaweiIDResponse.state, request.state);

      return Promise.reject();
    }

    return loginWithHuaweiIDResponse.data!;
  }

  state(): State {
    if (!this._accessToken || !this._refreshToken || !this._expiredAt) {
      return State.EMPTY_AUTHORIZATION;
    }

    // 提前5分钟刷新 token
    if (dateformat.create(this._expiredAt).isBefore(dateformat.now().add(5, 'minute'))) {
      return State.NEED_REFRESH;
    }

    // refresh_token 有效期30天，提前1天刷新
    if (this._authorizedAt && dateformat.create(this._authorizedAt).add(29, 'day').isBefore(dateformat.now())) {
      return State.REFRESH_TOKEN_EXPIRED;
    }

    return State.NORMAL;
  }

  async login(): Promise<Authorization> {
    const credential = await Authorization.loginWithHuaweiID();

    hilog.info(LogDomain.MODELS, 'models/auth', '认证信息, credential: %{public}s, client_id: %{public}s',
      JSON.stringify(credential));

    if ('undefined' === typeof credential) {
      hilog.error(LogDomain.MODELS, 'models/auth', '获取到的认证信息为空');

      return Promise.reject();
    }

    const response = await AccessToken.login(App.clientId, credential?.authorizationCode!);

    this._authorizedAt = new Date();
    this._accessToken = response.access_token;
    this._refreshToken = response.refresh_token;
    this._expiredAt = dateformat.now().add(response.expired_in, 'second').toDate() as Date;

    return this;
  }

  async refresh(refreshToken?: string): Promise<Authorization> {
    if ('undefined' === typeof refreshToken) {
      hilog.error(LogDomain.MODELS, 'models/auth', '传递的 refresh_token 参数错误');

      return Promise.reject();
    }

    const response = await AccessToken.loginRefresh(App.clientId, refreshToken!);

    this._authorizedAt = new Date();
    this._accessToken = response.access_token;
    this._refreshToken = response.refresh_token;
    this._expiredAt = dateformat.now().add(response.expired_in, 'second').toDate() as Date;

    return this;
  }

  clear(): void {
    this._authorizedAt = undefined;
    this._accessToken = undefined;
    this._refreshToken = undefined;
    this._expiredAt = undefined;
  }
}