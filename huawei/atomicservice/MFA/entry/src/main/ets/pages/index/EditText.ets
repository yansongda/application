import { application } from '@kit.AbilityKit';
import { AppStorageV2, KeyboardAvoidMode, LoadingDialogV2 } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Totp } from '../../api/Totp';
import { AppPagesName, LogDomain } from '../../App';
import { IInfoCardJumpResult } from '../../components/InfoCard';
import { ItemRuntime } from '../../models/totp/ItemRuntime';
import { Toast } from '../../utils/PromptAction';

// 编辑页路由参数：显式携带编辑模式，避免依赖路由名推断导致误写字段
export class EditTextParams {
  runtime: ItemRuntime | undefined = undefined;
  isIssuer: boolean = true;

  constructor(runtime: ItemRuntime | undefined, isIssuer: boolean) {
    this.runtime = runtime;
    this.isIssuer = isIssuer;
  }
}

@Builder
export function builder() {
  EditText()
}

// 发行方 / 用户名编辑共用页：由 isIssuer 切换标题、占位符与提交字段。
// 调用方按各自路由名 pushPathByName，参数为 EditTextParams（携带 runtime 与编辑模式）。
@ComponentV2
struct EditText {
  @Local
  private title: Resource | undefined = undefined;
  @Local
  private draft: string = '';
  private isIssuer: boolean = true;
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
            Text(this.pageTitle())
              .fontWeight(FontWeight.Bold)
              .fontSize($r('app.float.title_font_size'))
              .align(Alignment.Center)
          }

          TextInput({
            placeholder: this.placeholder(),
            text: this.draft
          })
            .defaultFocus(true)
            .onChange((value: string): void => {
              this.draft = value;
            })
            .onFocus(() => {
              this.title = this.pageTitle();
            })
            .onBlur(() => {
              this.title = undefined;
            })
        }

        Flex({ direction: FlexDirection.ColumnReverse }) {
          Button($r('app.string.ok'))
            .width('100%')
            .margin({ bottom: $r('app.integer.page_margin_smaller') })
            .onClick(async () => {
              await this.submit();
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
      const params = context.pathInfo.param as EditTextParams | undefined;

      if ('undefined' === typeof params || 'undefined' === typeof params.runtime) {
        return;
      }

      this.runtime = params.runtime;
      this.isIssuer = params.isIssuer;
      this.draft = this.currentValue();
      this.title = this.pageTitle();
    })
    .onWillHide(() => {
      this.runtime = undefined;
    });
  }

  @Builder
  loadingDialog() {
    LoadingDialogV2({
      content: $r('app.string.handling'),
    })
  }

  @Builder
  titleBuilder() {
    Row() {
      Text(this.title)
        .fontWeight(FontWeight.Bold)
        .fontSize($r('app.float.subtitle_font_size'))
        .margin({ left: 10 })
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
  }

  private pageTitle(): Resource {
    return this.isIssuer ? $r('app.string.index_edit_issuer_page_title') :
      $r('app.string.index_edit_username_page_title');
  }

  private placeholder(): Resource {
    return this.isIssuer ? $r('app.string.index_page_edit_issuer_placeholder') :
      $r('app.string.index_page_edit_username_placeholder');
  }

  // 编辑初值来自路由参数中的运行时对象
  private currentValue(): string {
    return (this.isIssuer ? this.runtime?.issuer : this.runtime?.username) ?? '';
  }

  private logPage(): AppPagesName {
    return this.isIssuer ? AppPagesName.INDEX_EDIT_ISSUER : AppPagesName.INDEX_EDIT_USERNAME;
  }

  // 空输入时回退到默认文案（走 string 资源，避免在代码里硬编码中文）
  private fallbackValue(): string {
    const value = this.isIssuer ? $r('app.string.index_edit_issuer_unknown') :
      $r('app.string.index_edit_username_unknown');

    try {
      return application.getApplicationContext().resourceManager.getStringSync(value.id);
    } catch (e) {
      hilog.warn(LogDomain.PAGES, this.logPage(), '读取默认文案失败: %{public}s', JSON.stringify(e));

      return '';
    }
  }

  private async submit(): Promise<void> {
    const id = this.runtime?.id ?? 'unknown';
    // 输入为空时回退到默认文案，避免把空值提交给服务端
    const value = this.draft.length > 0 ? this.draft : this.fallbackValue();

    hilog.info(LogDomain.PAGES, this.logPage(), '修改后的值: %{public}s', value);

    try {
      await Toast.execute(
        () => this.isIssuer ? Totp.editIssuer(id, value) : Totp.editUsername(id, value),
        () => this.loadingDialog(),
        $r('app.string.operation_success'),
      );

      this.pages.pop({ value: value } as IInfoCardJumpResult);
    } catch (e) {
      hilog.warn(LogDomain.PAGES, this.logPage(), '修改失败: %{public}s', JSON.stringify(e));
    }
  }
}
