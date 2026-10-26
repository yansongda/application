import { AppStorageV2, LoadingDialogV2 } from '@kit.ArkUI';
import { InputCard, InputCardItem } from '../../components/InputCard';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPagesName, LogDomain } from '../../App';
import { Toast } from '../../utils/PromptAction';
import { Totp } from '../../api/Totp';
import { Header } from '../../components/Header';
import { isBase32SecretValid, normalizeSecret } from '../../utils/Base32';

// 摘要算法下拉选项：与后端 Totp::algorithm() 可接受值一致
const ALGORITHM_OPTIONS: SelectOption[] = [
  { value: 'SHA1' },
  { value: 'SHA256' },
  { value: 'SHA512' }
];

@Builder
export function builder() {
  Index()
}

@ComponentV2
struct Index {
  @Local
  private period: string = '30';
  @Local
  private digits: string = '6';
  @Local
  private algorithm: string = 'SHA1';
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
        InputCard({
          title: $r('app.string.index_page_basic_information'),
          items: [
            new InputCardItem({
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
            new InputCardItem({
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

        InputCard({
          title: $r('app.string.index_page_config_information'),
          items: [
            new InputCardItem({
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
            new InputCardItem({
              title: $r('app.string.index_page_config_digits'),
              value: this.digits,
              placeholder: $r('app.string.please_input'),
              options: { type: InputType.Number, maxLength: 1 },
              callback: {
                onChange: (value) => {
                  this.digits = value;
                }
              }
            }),
            new InputCardItem({
              title: $r('app.string.index_page_config_algorithm'),
              value: this.algorithm,
              selectOptions: ALGORITHM_OPTIONS,
              callback: {
                onChange: (value) => {
                  this.algorithm = value;
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

              const period = Number(this.period);

              if (!Number.isInteger(period) || period <= 0) {
                Toast.show({ message: $r('app.string.index_create_page_period_error') });

                return;
              }

              const digits = Number(this.digits);

              if (!Number.isInteger(digits) || digits < 6 || digits > 8) {
                Toast.show({ message: $r('app.string.index_create_page_digits_error') });

                return;
              }

              const algorithm = this.algorithm;
              // 归一并校验密钥：后端会把 Base32 文本解码后重新编码入库，尾长非法或填充位非 0
              // 的密钥会被静默截断（例如 GGG → GE），必须在提交前拦住
              const secret = normalizeSecret(this.secret);

              if (!isBase32SecretValid(secret)) {
                Toast.show({ message: $r('app.string.index_create_page_secret_format_error') });

                return;
              }

              const label = `${encodeURIComponent(this.issuer)}:${encodeURIComponent(this.username)}`;
              const uri =
                `otpauth://totp/${label}?secret=${secret}&issuer=${encodeURIComponent(
                  this.issuer)}&period=${period}&digits=${digits}&algorithm=${algorithm}`;

              hilog.info(LogDomain.PAGES, AppPagesName.INDEX_CREATE, '新建: %{private}s', uri);

              try {
                await Toast.execute(
                  () => Totp.create(uri),
                  () => this.loadingDialog(),
                  $r('app.string.operation_success'),
                );

                this.pages.pop();
              } catch (e) {
                hilog.warn(LogDomain.PAGES, AppPagesName.INDEX_CREATE, '新建 TOTP 失败: %{public}s',
                  JSON.stringify(e));
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