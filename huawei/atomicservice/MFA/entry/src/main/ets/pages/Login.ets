import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPagesName, LogDomain } from '../App';
import { Authorization, State } from '../models/Auth';
import {
  AdvancedDialogV2Button, AlertDialogV2, AppStorageV2, LoadingDialogV2, PersistenceV2
} from '@kit.ArkUI';
import { Dialog } from '../utils/PromptAction';
import { User } from '../models/User';
import { User as UserApi } from '../api/User';
import { SecuritySync } from '../models/security/Sync';
import { AuthGate } from '../utils/AuthGate';
import { AuthExpiredError } from '../utils/Errors';

// 重试按钮与关闭重试框之间的让位时间（alert 自带关闭动画，立刻开 loading 会短暂同屏）
const RETRY_DELAY_MS: number = 200;

export interface LoginPageParams {
  forceAuthorizationState: State;
}

enum AuthType {
  LOGIN,
  LOGIN_REFRESH,
}

@Builder
export function builder() {
  Login()
}

@ComponentV2
struct Login {
  private pages: NavPathStack = AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;
  private authorization: Authorization =
    PersistenceV2.globalConnect({ type: Authorization, defaultCreator: () => new Authorization() })!;
  private user: User =
    PersistenceV2.globalConnect({ type: User, defaultCreator: () => new User() })!;
  @Local
  private failed: boolean = false;
  @Local
  private lastAuthType: AuthType = AuthType.LOGIN;
  // 认证重入锁：onReady 与重试按钮可能并发触发，多个流程会各自抢 loading 窗口
  private isAuthenticating: boolean = false;

  build() {
    NavDestination() {
      Column() {
        Image($r('app.media.icon')).width('30%');
        Text($r('app.string.login_page_login')).fontSize(20).margin({ top: 20 });

        if (this.failed) {
          Button($r('app.string.retry'))
            .margin({ top: 30 })
            .onClick(() => {
              this.auth(this.lastAuthType);
            })
        }
      }
      .width('100%')
      .height('100%')
      .margin({ top: $r('app.integer.page_margin') })
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .hideTitleBar(true)
    .onReady(async (context: NavDestinationContext) => {
      const loginState = [State.EMPTY_AUTHORIZATION, State.REFRESH_TOKEN_EXPIRED];
      const refreshState = [State.NEED_REFRESH];
      const state = this.getFinalState(context.pathInfo.param as LoginPageParams);

      hilog.info(LogDomain.PAGES, AppPagesName.LOGIN, 'onReady, state: %{public}s', state.toString());

      // 认证状态已被其它流程恢复（例如延迟入栈期间 refresh 完成）：直接关闭登录页，避免停在空页
      if (!loginState.includes(state) && !refreshState.includes(state)) {
        this.popIfSelf();

        return;
      }

      if (loginState.includes(state)) {
        await this.auth(AuthType.LOGIN);
      }

      if (refreshState.includes(state)) {
        await this.auth(AuthType.LOGIN_REFRESH);
      }
    });
  }

  @Builder
  loadingDialog() {
    LoadingDialogV2({
      content: $r('app.string.login_page_login'),
    })
  }

  @Builder
  loginConfirmDialog(action: () => void) {
    AlertDialogV2({
      primaryTitle: $r('app.string.home_page_login_failed_title'),
      content: $r('app.string.is_retry'),
      primaryButton: new AdvancedDialogV2Button({
        content: $r('app.string.cancel'),
      }),
      secondaryButton: new AdvancedDialogV2Button({
        content: $r('app.string.retry'),
        role: ButtonRole.ERROR,
        action
      }),
    })
  }

  private async auth(type: AuthType): Promise<void> {
    if (this.isAuthenticating) {
      return;
    }

    this.isAuthenticating = true;
    this.lastAuthType = type;
    this.failed = false;

    // 整个认证流程只开一个 loading：refresh 失败时在同一窗口内降级登录，
    // 不再「关掉 → 重开 → 递归 auth」，否则接口在超时边界抖动时会在两个 loading 之间来回闪
    await Dialog.openLoading(() => this.loadingDialog());

    try {
      if (AuthType.LOGIN_REFRESH === type) {
        try {
          await this.authorization.refresh(this.authorization.refreshToken);
        } catch (e) {
          hilog.warn(LogDomain.PAGES, AppPagesName.LOGIN,
            'refresh_token 刷新失败，可能过期或服务器错误，重新登录， Cause: %{public}s',
            JSON.stringify(e));

          await this.authorization.login();

          this.lastAuthType = AuthType.LOGIN;
        }
      } else {
        await this.authorization.login();
      }

      // 先让认证 loading 完全退场，再回首页：否则首页 onActive 的刷新 loading 会与它同屏
      await Dialog.closeLoading();

      AuthGate.reset();

      // 先跳转再补用户信息：列表渲染只依赖 itemsRuntime，头像/昵称由全局 User（@ObservedV2/@Trace）异步刷新。
      // 若把 fetchUser 串在跳转前，会在登录页多等一次与列表无关的请求（网络差时至多 5s 超时），表现为「登录成功却卡住」。
      this.popIfSelf();

      this.fetchUser().catch(() => {
        // fetchUser 内部已吞掉异常，这里仅避免 unhandled rejection
      });
    } catch (e) {
      await Dialog.closeLoading();

      // 认证失效已由拦截器跳转登录页，这里再弹重试框只会叠在登录页上方；保留页面内重试按钮
      if (!(e instanceof AuthExpiredError)) {
        await Dialog.openAlert(() => this.loginConfirmDialog(() => {
          // 按钮 action 是同步回调：延迟一拍，等重试框关闭动画结束再开 loading
          setTimeout(() => {
            this.auth(this.lastAuthType).catch(() => {
              // 失败已在 auth 内部处理，仅避免 unhandled rejection
            });
          }, RETRY_DELAY_MS);
        }));
      }

      // 用户在重试对话框选择取消，停留在登录页并提供重试按钮
      hilog.warn(LogDomain.PAGES, AppPagesName.LOGIN, '登录失败: %{public}s', JSON.stringify(e));

      this.failed = true;
    } finally {
      this.isAuthenticating = false;
    }
  }

  // 登录成功后拉取一次用户信息，失败不阻塞登录流程
  private async fetchUser(): Promise<void> {
    try {
      const user = await UserApi.detail();

      // 必须逐字段原地更新：user 是接口返回的普通 JSON 对象，
      // 整体替换 this.user.config 会让被观测的 Config 实例失效，后续修改不再刷新 UI
      this.user.apply(user);

      // 安全设置调和（本地优先）：在用户信息回来之后做一次，之后不再用远端覆盖本地
      const context = this.getUIContext().getHostContext();

      if ('undefined' !== typeof context) {
        SecuritySync.reconcile(context, user.config?.mfa?.security);
      }
    } catch (e) {
      hilog.warn(LogDomain.PAGES, AppPagesName.LOGIN, '获取用户信息失败: %{public}s', JSON.stringify(e));
    }
  }

  // 用户可能已用返回手势关掉登录页：只有登录页仍在栈顶时才 pop，
  // 否则会把下层页面误关掉（例如从 user/detail 触发重新认证时）
  private popIfSelf(): void {
    const pathNames: string[] = this.pages.getAllPathName();

    if (AppPagesName.LOGIN.toString() === (pathNames[pathNames.length - 1] ?? '')) {
      this.pages.pop();
    }
  }

  private getFinalState(pageParams: LoginPageParams): State {
    const forceAuthorizationState: State | undefined = pageParams?.forceAuthorizationState;
    const currentAuthorizationState = this.authorization.state();

    return forceAuthorizationState ?? currentAuthorizationState;
  }
}
