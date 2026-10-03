import { authentication } from '@kit.AccountKit';
import { AdvancedDialogV2Button, AlertDialogV2, AppStorageV2, LoadingDialogV2, PersistenceV2 } from '@kit.ArkUI';
import { Card, CardItem } from '../../components/Card';
import { User } from '../../models/User';
import { Authorization } from '../../models/Auth';
import { ItemsRuntime } from '../../models/Runtime';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Dialog } from '../../utils/PromptAction';
import { User as UserApi } from '../../api/User';
import { App, AppPagesName, LogDomain } from '../../App';
import { displayOr } from '../../utils/Display';

@Builder
export function builder() {
  Detail()
}

@ComponentV2
struct Detail {
  @Local
  private user: User =
    PersistenceV2.globalConnect({ type: User, defaultCreator: () => new User() })!;
  @Local
  private itemsRuntime: ItemsRuntime = AppStorageV2.connect(ItemsRuntime, () => new ItemsRuntime())!;

  build() {
    NavDestination() {
      Column({ space: $r('app.integer.column_space') }) {
        Image(displayOr(this.user.config.avatar, $r('app.media.default_avatar')))
          .width('25%')
          .autoResize(false)
          .interpolation(ImageInterpolation.High)
          .borderRadius(10)
          .onError(() => {
            hilog.warn(LogDomain.PAGES, AppPagesName.USER_DETAIL, '头像加载失败，保持当前展示');
          })
          .onClick(() => {
            this.changeAvatar();
          })

        // 账号统计行（原「我的」页合并进来）：ItemsRuntime 未初始化时 ids 缺失，按 0 展示
        Text($r('app.string.user_detail_page_protected', this.protectedCount))
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('sys.color.font_tertiary'))

        Card({
          items: [
            new CardItem({
              title: $r('app.string.user_detail_page_nickname'),
              value: displayOr(this.user.config.nickname, $r('app.string.default_nickname')),
              eventClick: {
                action: async (): Promise<string | undefined> => {
                  const credential = await this.authorizeProfile();

                  // 授权失败或用户取消，返回 undefined 保持原有昵称显示
                  if (!credential?.nickName) {
                    return undefined;
                  }

                  return await this.editNickName(credential.nickName);
                },
              }
            }),
            new CardItem({
              title: $r('app.string.user_detail_page_slogan'),
              value: displayOr(this.user.config.slogan, $r('app.string.default_slogan')),
              eventClick: {
                action: AppPagesName.USER_EDIT_SLOGAN,
              },
            }),
          ]
        })

        Card({
          title: $r('app.string.user_page_information'),
          items: [
            new CardItem({
              title: $r('app.string.user_detail_page_phone'),
              value: $r('app.string.user_detail_page_coming_soon'),
            }),
          ]
        })

        Card({
          title: $r('app.string.more'),
          items: [
            new CardItem({
              title: $r('app.string.help_entry'),
              value: '',
              eventClick: { action: AppPagesName.HELP },
            }),
            new CardItem({
              title: $r('app.string.user_detail_page_about'),
              value: $r('app.string.user_detail_page_version', App.version),
            }),
            new CardItem({
              title: $r('app.string.user_detail_page_delete_account'),
              value: '',
              eventClick: { action: AppPagesName.USER_DELETE },
            }),
          ]
        })
      }
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .title($r('app.string.user_detail_page_name'))
  }

  // 统计行兜底：ItemsRuntime 可能尚未初始化，ids 缺失时按 0 展示
  private get protectedCount(): number {
    const ids: string[] | undefined = this.itemsRuntime.ids;

    return 'undefined' === typeof ids ? 0 : ids.length;
  }

  // 请求华为账号 profile 授权，失败或用户取消时返回 undefined
  private async authorizeProfile(): Promise<authentication.AuthorizationWithHuaweiIDCredential | undefined> {
    let credential: authentication.AuthorizationWithHuaweiIDCredential;

    try {
      credential =
        await Authorization.authenticateWithHuaweiID(['profile'], this.getUIContext().getHostContext());
    } catch (e) {
      hilog.warn(LogDomain.PAGES, AppPagesName.USER_DETAIL, '华为账号授权失败或已取消: %{public}s', JSON.stringify(e));

      return undefined;
    }

    hilog.info(LogDomain.PAGES, AppPagesName.USER_DETAIL, '授权获取的用户信息: %{private}s',
      JSON.stringify(credential));

    return credential;
  }

  private async changeAvatar(): Promise<void> {
    const credential = await this.authorizeProfile();
    const avatarUri: string | null | undefined = credential?.avatarUri;

    if ('undefined' === typeof avatarUri || null === avatarUri || 0 === avatarUri.length) {
      hilog.warn(LogDomain.PAGES, AppPagesName.USER_DETAIL, '华为账号未返回头像，保持原头像');

      return;
    }

    try {
      await Dialog.execute(
        () => this.loadingDialog(),
        () => UserApi.editAvatar(avatarUri),
        () => this.editConfirmDialog(() => this.editAvatar(avatarUri)),
      );

      this.user.config.avatar = avatarUri;

      hilog.info(LogDomain.PAGES, AppPagesName.USER_DETAIL, '头像已更新，uri 长度: %{public}d', avatarUri.length);
    } catch (e) {
      // 用户取消重试，保持原头像
    }
  }

  @Builder
  loadingDialog() {
    LoadingDialogV2({
      content: $r('app.string.handling'),
    })
  }

  @Builder
  editConfirmDialog(action: () => void) {
    AlertDialogV2({
      primaryTitle: $r('app.string.user_detail_page_edit_failed'),
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

  private async editAvatar(avatarUri: string): Promise<void> {
    try {
      await Dialog.execute(
        () => this.loadingDialog(),
        () => UserApi.editAvatar(avatarUri),
        () => this.editConfirmDialog(() => this.editAvatar(avatarUri)),
      );

      this.user.config.avatar = avatarUri;
    } catch (e) {
      // 用户取消重试，保持原头像
    }
  }

  private async editNickName(nickName: string): Promise<string | undefined> {
    try {
      await Dialog.execute(
        () => this.loadingDialog(),
        () => UserApi.editNickname(nickName),
        () => this.editConfirmDialog(() => this.editNickName(nickName)),
      );

      this.user.config.nickname = nickName;

      return nickName;
    } catch (e) {
      // 用户取消重试，返回 undefined 保持原有昵称显示
      return undefined;
    }
  }
}
