import { authentication } from '@kit.AccountKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { App, LogDomain } from '../App';
import { AccessToken } from '../api/AccessToken';
import { Context } from '@kit.AbilityKit';
import { AuthExpiredError } from '../utils/Errors';
import { AuthSnapshot, computeAuthState } from '../utils/AuthStatePolicy';
import { State } from '../types/Session';

// 登录态（持久化 + 网络动作）。
//
// 注意 `@ObservedV2` / `@Trace`：这是 **PersistenceV2 的持久化要求**（类要 @ObservedV2、持久化字段要 @Trace），
// 不是给 UI 订阅用的——当前没有任何 `build()` 读这里的数据。删掉它们会让 token 不再落盘（每次冷启动都要重新登录）。
@ObservedV2
export class Authorization {
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
        JSON.stringify(error));

      return Promise.reject(new Error('华为账号授权失败，请重试'));
    }

    if (authenticateWithHuaweiIDResponse.state && request.state !== authenticateWithHuaweiIDResponse.state) {
      hilog.error(LogDomain.MODELS, 'models/auth',
        '华为账号授权失败(authenticateWithHuaweiID)，state 不同: %{public}s != %{public}s',
        authenticateWithHuaweiIDResponse.state, request.state);

      return Promise.reject(new Error('华为账号授权失败，请重试'));
    }

    // `code === 0` 不等于授权信息可用：data 缺失时后续 `credential.authorizationCode` 会拿到
    // undefined 并直接进请求体（表现为「授权成功但登录接口报参数错误」），必须在这里拦下
    const data: authentication.AuthorizationWithHuaweiIDCredential | undefined = authenticateWithHuaweiIDResponse.data;

    if ('undefined' === typeof data || null === data) {
      hilog.error(LogDomain.MODELS, 'models/auth', '华为账号授权未返回授权信息(authenticateWithHuaweiID)');

      return Promise.reject(new Error('华为账号授权失败，请重试'));
    }

    return data;
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
        JSON.stringify(error));

      return Promise.reject(new Error('华为账号登录失败，请重试'));
    }

    if (loginWithHuaweiIDResponse.state && request.state !== loginWithHuaweiIDResponse.state) {
      hilog.error(LogDomain.MODELS, 'models/auth',
        '华为账号登录失败(loginWithHuaweiID)，state 不同: %{public}s != %{public}s',
        loginWithHuaweiIDResponse.state, request.state);

      return Promise.reject(new Error('华为账号登录失败，请重试'));
    }

    const data: authentication.LoginWithHuaweiIDCredential | undefined = loginWithHuaweiIDResponse.data;

    if ('undefined' === typeof data || null === data) {
      hilog.error(LogDomain.MODELS, 'models/auth', '华为账号登录未返回登录信息(loginWithHuaweiID)');

      return Promise.reject(new Error('华为账号登录失败，请重试'));
    }

    return data;
  }

  state(): State {
    return computeAuthState(this.snapshot(), Date.now());
  }

  // 统一认证入口：调用方只声明「目标状态」，不再自己写 refresh → login 的降级分支。
  // - NORMAL：空操作
  // - NEED_REFRESH 且本地有 refresh_token：先刷新；只有 refresh_token 本身失效（AuthExpiredError）才降级完整登录，
  //   网络 / 服务端错误直接抛给页面重试（不强制拉起华为账号授权）
  // - 其余（EMPTY_AUTHORIZATION / REFRESH_TOKEN_EXPIRED / NEED_REFRESH 但本地无 refresh_token）：完整登录
  //   最后一个分支不能漏：强制 NEED_REFRESH（拦截器按响应码给的）遇到本地刚 clear 过 token 时，
  //   refresh 必然失败，若还 rethrow 给页面，用户点重试会永远停在登录页、走不到 login()。
  //   `REFRESH_TOKEN_EXPIRED` 只由拦截器（1005/1006）给出，即 refresh_token 已确定失效，直接完整登录，
  //   不再拿它去试 refresh（那一轮请求注定失败）。
  //
  // **只应由登录页调用**：这个方法会走 `login()`，也就是会拉起华为账号授权。
  // 非登录页（首页静默续期等）请用 `refreshOnly()`，否则「token 失效」会在两个页面各触发一次完整登录。
  async ensure(target?: State): Promise<void> {
    const state: State = 'undefined' === typeof target ? this.state() : target;

    if (State.NORMAL === state) {
      return;
    }

    if (State.NEED_REFRESH === state && 'undefined' !== typeof this.refreshToken) {
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

  // 只续期，不做交互式登录：供**非登录页**使用（首页 `onActive` 静默续期）。
  // - refresh_token 缺失 / 失效：抛 AuthExpiredError，由 SessionGuard 负责跳登录页；
  // - 网络 / 服务端错误：原样抛给调用方，由调用方决定是否重试（绝不在这里拉起华为账号授权）。
  async refreshOnly(): Promise<void> {
    await this.refresh(this.refreshToken);
  }

  async login(): Promise<Authorization> {
    const credential = await Authorization.loginWithHuaweiID();

    hilog.info(LogDomain.MODELS, 'models/auth', '认证信息, credential: %{private}s',
      JSON.stringify(credential));

    if ('undefined' === typeof credential) {
      hilog.error(LogDomain.MODELS, 'models/auth', '获取到的认证信息为空');

      return Promise.reject(new Error('华为账号授权失败，请重试'));
    }

    const code: string | undefined = credential?.authorizationCode;

    if ('undefined' === typeof code || 0 === code.length) {
      hilog.error(LogDomain.MODELS, 'models/auth', '华为账号授权未返回 authorizationCode');

      return Promise.reject(new Error('华为账号授权失败，请重试'));
    }

    const response = await AccessToken.login(App.clientId, code);

    this.apply(response.access_token, response.refresh_token, response.expired_in);

    return this;
  }

  async refresh(refreshToken?: string): Promise<Authorization> {
    if ('undefined' === typeof refreshToken) {
      hilog.error(LogDomain.MODELS, 'models/auth', '传递的 refresh_token 参数错误');

      // 本地已无 refresh_token，属「认证失效」而非业务错误：用 AuthExpiredError，
      // `ensure()` 据此降级为完整登录（用它当普通 HttpError 会让调用方停在失败重试上）。
      return Promise.reject(new AuthExpiredError('登录状态已失效，请重新登录'));
    }

    const response = await AccessToken.loginRefresh(App.clientId, refreshToken!);

    this.apply(response.access_token, response.refresh_token, response.expired_in);

    return this;
  }

  clear(): void {
    this._accessToken = undefined;
    this._refreshToken = undefined;
    this._expiredAt = undefined;
  }

  // 判定用的快照：只读，纯数据，供 `AuthStatePolicy` 使用
  private snapshot(): AuthSnapshot {
    // PersistenceV2 的持久化是 JSON 往返：`Date` 字段冷启动后可能已经是字符串，
    // 直接调 `getTime()` 会在冷启动时抛异常（登录态判定整体挂掉）。统一走字符串 → Date 归一。
    const expiredAtMs: number | undefined = 'undefined' === typeof this._expiredAt
      ? undefined
      : new Date(this._expiredAt.toString()).getTime();

    return { accessToken: this._accessToken, refreshToken: this._refreshToken, expiredAtMs: expiredAtMs };
  }

  // 落库的唯一入口：login / refresh 两条路径必须写同一组字段，
  // 否则会出现「有 access_token 没有 expiredAt」这种让 `state()` 退化成 EMPTY 的半登录态
  private apply(accessToken: string, refreshToken: string, expiredIn: number): void {
    this._accessToken = accessToken;
    this._refreshToken = refreshToken;
    this._expiredAt = new Date(Date.now() + expiredIn * 1000);
  }
}
