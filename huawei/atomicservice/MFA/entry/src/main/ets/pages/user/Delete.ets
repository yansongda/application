import { User as UserApi } from '../../api/User';
import { Config, User } from '../../models/User';
import { Authorization } from '../../models/Auth';
import { AppPagesName } from '../../App';
import { Toast } from '../../utils/PromptAction';
import { AppStorageV2, LoadingDialogV2, PersistenceV2 } from '@kit.ArkUI';

@Builder
export function builder() {
  Delete()
}

@ComponentV2
struct Delete {
  @Local
  private isChecked: boolean = false;
  private pages: NavPathStack = AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;
  private user: User =
    PersistenceV2.globalConnect({ type: User, defaultCreator: () => new User() })!;
  private authorization: Authorization =
    PersistenceV2.globalConnect({ type: Authorization, defaultCreator: () => new Authorization() })!;

  build() {
    NavDestination() {
      Flex({ direction: FlexDirection.Column }) {
        Column({ space: $r('app.integer.column_space') }) {
          Text($r('app.string.user_delete_page_notice'))

          Column({ space: 5 }) {
            Text($r('app.string.user_delete_page_operation'))

            Text($r('app.string.user_delete_page_operation_delete_profile'))
              .fontWeight(FontWeight.Medium)
            Text($r('app.string.user_delete_page_operation_delete_totp'))
              .fontWeight(FontWeight.Medium)
          }
          .alignItems(HorizontalAlign.Start)
        }
        .alignItems(HorizontalAlign.Start)

        Flex({ direction: FlexDirection.ColumnReverse }) {
          Button($r('app.string.user_delete_page_delete_button'), { type: ButtonType.ROUNDED_RECTANGLE })
            .enabled(this.isChecked)
            .width('100%')
            .backgroundColor($r('sys.color.warning'))
            .onClick(async () => {
              if (!this.isChecked) {
                return;
              }

              try {
                await Toast.execute(
                  () => UserApi.delete(),
                  () => this.loadingDialog(),
                  $r('app.string.operation_success'),
                );
              } catch (e) {
                // 失败已通过 Toast 提示，保留当前状态
                return;
              }

              // 注销成功后清理本地登录态与用户数据，并回登录页
              this.authorization.clear();
              this.user.config = new Config();
              this.user.phone = undefined;

              this.pages.clear();
              this.pages.pushPathByName(AppPagesName.LOGIN, null);
            })

          Row() {
            Checkbox({ name: 'checkbox1', group: 'checkboxGroup' })
              .select(this.isChecked)
              .shape(CheckBoxShape.CIRCLE)

            Text($r('app.string.user_delete_page_delete_confirm'))
          }
          .onClick(() => {
            this.isChecked = !this.isChecked;
          })
          .margin({ bottom: 10 })
        }
      }
      .padding({ left: $r('app.integer.page_padding'), right: $r('app.integer.page_padding') })
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .title($r('app.string.user_detail_page_delete_account'))
  }

  @Builder
  loadingDialog(content?: Resource) {
    LoadingDialogV2({
      content: content ?? $r('app.string.handling'),
    })
  }
}