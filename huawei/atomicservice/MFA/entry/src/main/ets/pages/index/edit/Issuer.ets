import { Totp } from '../../../api/Totp';
import { Toast } from '../../../utils/PromptAction';
import { AppStorageV2, KeyboardAvoidMode, LoadingDialogV2 } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPagesName, LogDomain } from '../../../App';
import { ItemRuntime } from '../../../models/Runtime';
import { IJumpCallbackResult } from '../../../components/Card';

@Builder
export function builder() {
  Issuer()
}

@ComponentV2
struct Issuer {
  @Local
  private title: Resource | undefined = $r('app.string.index_edit_issuer_page_title');
  private pages: NavPathStack = AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;
  private runtime: ItemRuntime | undefined = undefined;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
  }

  build() {
    NavDestination() {
      Flex({ direction: FlexDirection.Column }) {
        Column({ space: $r('app.integer.column_space_biggest') }) {
          if (!this.title) {
            Text($r('app.string.index_edit_issuer_page_title'))
              .fontWeight(FontWeight.Bold)
              .fontSize(30)
              .align(Alignment.Center)
          }

          TextInput({
            placeholder: $r('app.string.index_page_edit_issuer_placeholder'),
            text: this.runtime!.issuer!!
          })
            .defaultFocus(true)
            .onFocus(() => {
              this.title = $r('app.string.index_edit_issuer_page_title');
            })
            .onBlur(() => {
              this.title = undefined;
            })
        }

        Flex({ direction: FlexDirection.ColumnReverse }) {
          Button($r('app.string.ok'))
            .width('100%')
            .margin({ bottom: 30 })
            .onClick(async () => {
              const issuer = this.runtime?.issuer ?? '未知发行方';

              hilog.info(LogDomain.PAGES, AppPagesName.INDEX_EDIT_ISSUER, '修改后的值: %{public}s', issuer);

              try {
                await Toast.execute(
                  () => Totp.editIssuer(this.runtime?.id ?? 'unknown', issuer),
                  () => this.loadingDialog(),
                  $r('app.string.operation_success'),
                );

                this.pages.pop({ value: issuer } as IJumpCallbackResult);
              } catch (e) {
                hilog.warn(LogDomain.PAGES, AppPagesName.INDEX_EDIT_ISSUER, '修改发行方失败: %{public}s',
                  JSON.stringify(e));
              }
            })
        }
      }
      .margin({ top: $r('app.integer.page_margin_smaller') })
      .padding({ left: $r('app.integer.page_padding'), right: $r('app.integer.page_padding') })
    }
    .mode(NavDestinationMode.DIALOG)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .backgroundColor($r('sys.color.background_secondary'))
    .title(this.titleBuilder())
    .onReady((context: NavDestinationContext) => {
      this.runtime = context.pathInfo.param as ItemRuntime;
    })
    .onWillHide(() => {
      this.runtime = undefined;
    });
  }

  @Builder
  titleBuilder() {
    Row() {
      Text(this.title)
        .fontWeight(FontWeight.Bold)
        .fontSize(20)
        .margin({ left: 10 })
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  loadingDialog(content?: Resource) {
    LoadingDialogV2({
      content: content ?? $r('app.string.handling'),
    })
  }
}