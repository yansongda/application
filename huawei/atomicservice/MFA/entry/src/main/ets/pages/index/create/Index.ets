import { AppStorageV2, LoadingDialogV2 } from '@kit.ArkUI';
import { CardInput, CardInputItem } from '../../../components/Card';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPagesName, LogDomain } from '../../../App';
import { Toast } from '../../../utils/PromptAction';
import { Totp } from '../../../api/Totp';
import { Header } from '../../../components/Header';

@Builder
export function builder() {
  Index()
}

@ComponentV2
struct Index {
  @Local
  private period: string = '30';
  @Local
  private issuer?: string = undefined;
  @Local
  private username?: string = undefined;
  @Local
  private secret?: string = undefined;
  @Local
  private secretError?: ResourceStr = '';
  private pages: NavPathStack = AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;

  build() {
    NavDestination() {
      Column({ space: $r('app.integer.column_space') }) {
        CardInput({
          title: $r('app.string.index_page_basic_information'),
          items: [
            new CardInputItem({
              title: $r('app.string.index_page_issuer'),
              value: this.issuer,
              placeholder: $r('app.string.index_page_edit_issuer_placeholder'),
              options: { maxLength: 120 },
              callback: {
                onChange: (value) => {
                  this.issuer = value;
                }
              }
            }),
            new CardInputItem({
              title: $r('app.string.index_page_username'),
              value: this.username,
              placeholder: $r('app.string.index_page_edit_username_placeholder'),
              options: { maxLength: 120 },
              callback: {
                onChange: (value) => {
                  this.username = value;
                }
              }
            }),
          ]
        })

        CardInput({
          title: $r('app.string.index_page_config_information'),
          items: [
            new CardInputItem({
              title: $r('app.string.index_page_config_period'),
              value: this.period,
              placeholder: $r('app.string.please_input'),
              options: { type: InputType.Number },
              callback: {
                onChange: (value) => {
                  this.period = value;
                }
              }
            }),
          ]
        })

        Column({ space: $r('app.integer.column_space') }) {
          Column({ space: $r('app.integer.column_space_smaller') }) {
            Header({ title: $r('app.string.index_create_page_secret'), textMargin: { left: 30 } })

            TextArea({
              placeholder: $r('app.string.index_page_edit_secret_placeholder'),
              text: this.secret,
            })
              .backgroundColor($r('sys.color.background_primary'))
              .minLines(3)
              .enableAutoFill(false)
              .onChange((value) => {
                this.secretError = undefined;
                this.secret = value.toUpperCase();
              })
              .inputFilter('^[A-Za-z2-7]{1,}$', () => {
                this.secretError = $r('app.string.index_create_page_secret_error');
              })

            if (this.secretError) {
              Text(this.secretError)
                .fontColor($r('sys.color.warning'))
                .textAlign(TextAlign.Start)
                .alignSelf(ItemAlign.Start)
            }
          }

          Button($r('app.string.index_create_page_create_button'))
            .width('100%')
            .margin({ bottom: 30 })
            .onClick(async () => {
              if (!this.issuer || this.issuer.trim().length === 0 || !this.username ||
                this.username.trim().length === 0 || !this.secret || this.secret.trim().length === 0) {
                Toast.show({ message: $r('app.string.index_create_page_info_error') });

                return;
              }

              const period = Number.parseInt(this.period);

              if (Number.isNaN(period) || period <= 0) {
                Toast.show({ message: $r('app.string.index_create_page_period_error') });

                return;
              }

              const label = `${encodeURIComponent(this.issuer)}:${encodeURIComponent(this.username)}`;
              const uri =
                `otpauth://totp/${label}?secret=${this.secret}&issuer=${encodeURIComponent(this.issuer)}&period=${period}`;

              hilog.info(LogDomain.PAGES, AppPagesName.INDEX_CREATE, '新建: %{public}s', uri);

              try {
                await Toast.execute(
                  () => Totp.create(uri),
                  () => this.loadingDialog(),
                  $r('app.string.operation_success'),
                );

                this.pages.pop();
              } catch (e) {
              }
            })
        }
        .padding({ left: $r('app.integer.page_padding'), right: $r('app.integer.page_padding') })
      }
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .title($r('app.string.index_create_page_title'))
  }

  @Builder
  loadingDialog(content?: Resource) {
    LoadingDialogV2({
      content: content ?? $r('app.string.handling'),
    })
  }
}