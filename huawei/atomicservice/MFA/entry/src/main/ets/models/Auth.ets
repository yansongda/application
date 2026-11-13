import { authentication } from '@kit.AccountKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { App, LogDomain } from '../App';
import { dateformat } from '@developers/dateformat';
import { AccessToken } from '../api/AccessToken';
import { Context } from '@kit.AbilityKit';
import { AuthExpiredError, HttpError } from '../utils/Errors';
import { State } from '../types/Session';

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

  static async authenticateWithHuaweiID(scopes?: string[],
    context?: Context): Promise<authentication.AuthorizationWithHuaweiIDCredential> {
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
      // 元服务虽要求已登录，但仍可能因 App 指纹校验失败、网络异常、用户取消等原因抛错
      hilog.error(LogDomain.MODELS, 'models/auth', '华为账号授权失败(authenticateWithHuaweiID): %{public}s',
        JSON.stringify(error))

      return Promise.reject();
    }

    if (authenticateWithHuaweiIDResponse.state && request.state !== authenticateWithHuaweiIDResponse.state) {
      hilog.error(LogDomain.MODELS, 'models/auth',
        '华为账号授权失败(authenticateWithHuaweiID)，state 不同: %{public}s != %{public}s',
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
      // 元服务虽要求已登录，但仍可能因 App 指纹校验失败、网络异常、用户取消等原因抛错
      hilog.error(LogDomain.MODELS, 'models/auth', '华为账号登录失败(loginWithHuaweiID): %{public}s',
        JSON.stringify(error))

      return Promise.reject();
    }

    if (loginWithHuaweiIDResponse.state && request.state !== loginWithHuaweiIDResponse.state) {
      hilog.error(LogDomain.MODELS, 'models/auth',
        '华为账号登录失败(loginWithHuaweiID)，state 不同: %{public}s != %{public}s',
        loginWithHuaweiIDResponse.state, request.state);

      return Promise.reject();
    }

    return loginWithHuaweiIDResponse.data!;
  }

  state(): State {
    if (!this._accessToken || !this._refreshToken || !this._expiredAt) {
      return State.EMPTY_AUTHORIZATION;
    }

    // 提前 5 分钟刷新 token
    if (dateformat.create(this._expiredAt).isBefore(dateformat.now().add(5, 'minute'))) {
      return State.NEED_REFRESH;
    }

    // refresh_token 有效期 30 天，提前 1 天刷新
    if (this._authorizedAt && dateformat.create(this._authorizedAt).add(29, 'day').isBefore(dateformat.now())) {
      return State.REFRESH_TOKEN_EXPIRED;
    }

    return State.NORMAL;
  }

  // 统一认证入口：调用方只声明「目标状态」，不再自己写 refresh → login 的降级分支。
  // - NORMAL：空操作
  // - NEED_REFRESH：先刷新；只有 refresh_token 本身失效（AuthExpiredError）才降级完整登录，
  //   网络 / 服务端错误直接抛给页面重试（不强制拉起华为账号授权）
  // - EMPTY_AUTHORIZATION / REFRESH_TOKEN_EXPIRED：完整登录
  async ensure(target?: State): Promise<void> {
    const state: State = 'undefined' === typeof target ? this.state() : target;

    if (State.NORMAL === state) {
      return;
    }

    if (State.NEED_REFRESH === state) {
      try {
        await this.refresh(this.refreshToken);

        return;
      } catch (e) {
        const error: Error = e as Error;

        if (!(error instanceof AuthExpiredError)) {
          throw error;
        }

        // refresh_token 失效：降级为完整登录
      }
    }

    await this.login();
  }

  async login(): Promise<Authorization> {
    const credential = await Authorization.loginWithHuaweiID();

    hilog.info(LogDomain.MODELS, 'models/auth', '认证信息, credential: %{private}s',
      JSON.stringify(credential));

    if ('undefined' === typeof credential) {
      hilog.error(LogDomain.MODELS, 'models/auth', '获取到的认证信息为空');

      return Promise.reject(new HttpError('华为账号授权失败，请重试'));
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

      return Promise.reject(new HttpError('登录状态已失效，请重新登录'));
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