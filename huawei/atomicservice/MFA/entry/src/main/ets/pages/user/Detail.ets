import { authentication } from '@kit.AccountKit';
import { AdvancedDialogV2Button, AlertDialogV2, AppStorageV2, LoadingDialogV2, PersistenceV2 } from '@kit.ArkUI';
import { InfoCard, InfoCardItem } from '../../components/InfoCard';
import { SettingCard } from '../../components/SettingCard';
import { User } from '../../models/User';
import { Authorization } from '../../models/Auth';
import { Security } from '../../models/Security';
import { AppLock, VerifyOutcome } from '../../models/AppLock';
import { ItemsRuntime } from '../../models/totp/ItemsRuntime';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Dialog, Toast } from '../../utils/PromptAction';
import { PrivacyWindow } from '../../utils/PrivacyWindow';
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
  @Local
  private security: Security = Security.shared();
  // 开关行的强制重建计数器：Toggle 自带内部状态，模型真值不变时不会回滚视觉（技术设计 R7）
  @Local
  private toggleRevision: number = 0;

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

        // 账号统计行：ItemsRuntime 未初始化时 ids 缺失，按 0 展示
        Text($r('app.string.user_detail_page_protected', this.protectedCount))
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('sys.color.font_tertiary'))

        InfoCard({
          items: [
            new InfoCardItem({
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
            new InfoCardItem({
              title: $r('app.string.user_detail_page_slogan'),
              value: displayOr(this.user.config.slogan, $r('app.string.default_slogan')),
              eventClick: {
                action: AppPagesName.USER_EDIT_SLOGAN,
              },
            }),
          ]
        })

        InfoCard({
          title: $r('app.string.user_page_information'),
          items: [
            new InfoCardItem({
              title: $r('app.string.user_detail_page_phone'),
              value: $r('app.string.user_detail_page_coming_soon'),
            }),
          ]
        })

        SettingCard({
          title: $r('app.string.user_detail_page_security'),
          revision: this.toggleRevision,
          items: [
            {
              title: $r('app.string.user_detail_page_screen_protect'),
              description: $r('app.string.user_detail_page_screen_protect_desc'),
              toggle: {
                isOn: this.security.screenProtect,
                action: (next: boolean): void => {
                  this.toggleScreenProtect(next);
                },
              },
            },
            {
              title: $r('app.string.user_detail_page_app_lock'),
              description: $r('app.string.user_detail_page_app_lock_desc'),
              toggle: {
                isOn: this.security.appLock,
                action: (next: boolean): void => {
                  this.toggleAppLock(next);
                },
              },
            },
          ]
        })

        InfoCard({
          title: $r('app.string.more'),
          items: [
            new InfoCardItem({
              title: $r('app.string.help_entry'),
              value: '',
              eventClick: { action: AppPagesName.HELP },
            }),
            new InfoCardItem({
              title: $r('app.string.user_detail_page_about'),
              value: $r('app.string.user_detail_page_version', App.version),
            }),
            new InfoCardItem({
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

  // 防截屏开关：先写盘（失败则内存已回滚、开关复位），再经 PrivacyWindow.apply 应用隐私窗口
  private toggleScreenProtect(next: boolean): void {
    // 先递增 revision 强制重建开关行：开关已随手指拨到新位置，而写盘失败 / 拿不到 context 时
    // 模型真值不变，只能靠重建把视觉拨回原位（技术设计 R7）
    this.toggleRevision++;

    const context = this.getUIContext().getHostContext();

    if ('undefined' === typeof context) {
      hilog.warn(LogDomain.PAGES, AppPagesName.USER_DETAIL, 'toggle_screen_protect: context_undefined');

      return;
    }
    if (!this.security.setScreenProtect(context, next)) {
      // 写盘失败：setScreenProtect 内已回滚内存值，这里提示「设置保存失败」并保持开关原位
      Toast.show({ message: $r('app.string.user_detail_page_setting_failed'), duration: 3000 });
      return;
    }
    PrivacyWindow.apply(next, 'setting');
  }

  // 应用锁开关：开启前必须通过系统认证，认证成功才写盘；关闭直接写盘
  private toggleAppLock(next: boolean): void {
    // 同 toggleScreenProtect：无论成功、取消、验证失败还是退后台打断，都强制重建开关行（R7）
    this.toggleRevision++;

    const context = this.getUIContext().getHostContext();

    if ('undefined' === typeof context) {
      hilog.warn(LogDomain.PAGES, AppPagesName.USER_DETAIL, 'toggle_app_lock: context_undefined');

      return;
    }
    if (next) {
      AppLock.shared().verify(context, (outcome: VerifyOutcome): void => {
        if (VerifyOutcome.SUCCESS === outcome) {
          // 成功不弹「已开启」提示（开关本身就是反馈）；但写盘失败必须提示，否则开关静默弹回、用户不知原因
          if (!this.security.setAppLock(context, true)) {
            Toast.show({ message: $r('app.string.user_detail_page_setting_failed'), duration: 3000 });
          }
          return;
        }
        if (VerifyOutcome.NO_CREDENTIAL === outcome) {
          Toast.show({ message: $r('app.string.user_detail_page_app_lock_no_credential'), duration: 3000 });
          return;
        }
        if (VerifyOutcome.SKIPPED !== outcome) {
          Toast.show({ message: $r('app.string.user_detail_page_app_lock_enable_failed'), duration: 3000 });
        }
      });
      return;
    }
    // 写盘失败时 setAppLock 会回滚内存值（开关随重建弹回原位），提示原因避免用户以为点了没反应
    if (!this.security.setAppLock(context, false)) {
      Toast.show({ message: $r('app.string.user_detail_page_setting_failed'), duration: 3000 });
    }
  }
}
