import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPagesName, LogDomain } from '../App';
import { Authorization, State } from '../models/Auth';
import {
  AdvancedDialogV2Button, AlertDialogV2, AppStorageV2, LoadingDialogV2, PersistenceV2
} from '@kit.ArkUI';
import { Dialog } from '../utils/PromptAction';
import { User } from '../models/User';
import { User as UserApi } from '../api/User';

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
    this.lastAuthType = type;
    this.failed = false;

    try {
      if (AuthType.LOGIN === type) {
        await Dialog.execute(
          () => this.loadingDialog(),
          () => this.authorization.login(),
          () => this.loginConfirmDialog(() => this.auth(type))
        );
      }

      if (AuthType.LOGIN_REFRESH === type) {
        const dialogId = await Dialog.open(() => this.loadingDialog());

        try {
          await this.authorization.refresh(this.authorization.refreshToken);

          Dialog.close(dialogId);
        } catch (e) {
          hilog.warn(LogDomain.PAGES, AppPagesName.LOGIN,
            'refresh_token 刷新失败，可能过期或服务器错误，重新登录， Cause: %{public}s',
            JSON.stringify(e))

          Dialog.close(dialogId);

          return this.auth(AuthType.LOGIN);
        }
      }

      await this.fetchUser();

      this.pages.pop();
    } catch (e) {
      // 用户在重试对话框选择取消，停留在登录页并提供重试按钮
      hilog.warn(LogDomain.PAGES, AppPagesName.LOGIN, '登录失败: %{public}s', JSON.stringify(e));

      this.failed = true;
    }
  }

  // 登录成功后拉取一次用户信息，失败不阻塞登录流程
  private async fetchUser(): Promise<void> {
    try {
      const user = await UserApi.detail();

      this.user.phone = user.phone;
      this.user.config = user.config;
    } catch (e) {
      hilog.warn(LogDomain.PAGES, AppPagesName.LOGIN, '获取用户信息失败: %{public}s', JSON.stringify(e));
    }
  }

  private getFinalState(pageParams: LoginPageParams): State {
    const forceAuthorizationState: State | undefined = pageParams?.forceAuthorizationState;
    const currentAuthorizationState = this.authorization.state();

    return forceAuthorizationState ?? currentAuthorizationState;
  }
}
