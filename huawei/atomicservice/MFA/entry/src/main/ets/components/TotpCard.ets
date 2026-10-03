import { DEFAULT_PERIOD, ItemRuntime } from '../models/Runtime';
import { Clipboard } from '../utils/Clipboard';
import { Toast } from '../utils/PromptAction';

// TOTP 列表项卡片内容：排序把手 + 发行方/用户名 + 验证码 + 周期进度
// 注意：ListItem 本体必须留在 List 的直接子节点（拖拽排序 onMove 依赖），这里只承载内容
@ComponentV2
export struct TotpCard {
  @Param runtime: ItemRuntime = ItemRuntime.empty();
  @Param isSortMode: boolean = false;

  build() {
    Column() {
      Row() {
        if (this.isSortMode) {
          SymbolGlyph($r('sys.symbol.line_3_horizontal'))
            .fontSize($r('app.float.icon_font_size'))
            .fontColor([$r('sys.color.font_tertiary')])
            .margin({ right: 10 })
        }

        Column() {
          Column() {
            Text(this.runtime.issuer)
              .fontSize($r('app.float.title_font_size'))
              .fontColor($r('sys.color.font_secondary'))
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          Column() {
            Text(this.runtime.username)
              .fontSize($r('app.float.caption_smaller_font_size'))
              .fontColor($r('sys.color.font_tertiary'))
              .textAlign(TextAlign.Center)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .margin({ top: 5 })
        }
        .layoutWeight(4)

        Column() {
          Text(this.runtime.code ?? '')
            .fontSize($r('app.float.code_font_size'))

          if (!this.isSortMode) {
            Button() {
              SymbolGlyph($r('sys.symbol.doc_filled_on_doc'))
                .fontSize($r('app.integer.action_icon_size'))
            }
            .type(ButtonType.Circle)
            .backgroundColor(Color.Transparent)
            .onClick(async () => {
              if ('undefined' === typeof this.runtime.code || this.runtime.code === '') {
                return;
              }

              try {
                await Clipboard.copy(this.runtime.code ?? '');

                Toast.show({ message: $r('app.string.index_index_page_copied'), duration: 3000 });
              } catch (e) {
                Toast.show({ message: $r('app.string.index_index_page_copy_failed'), duration: 3000 });
              }
            })
          }
        }
        .layoutWeight(6)
      }
      .height($r('app.integer.card_content_height'))
      .padding({ left: $r('app.integer.page_padding_smaller'), right: $r('app.integer.page_padding_smaller') })

      Progress({
        value: this.runtime.progress ?? DEFAULT_PERIOD,
        total: this.runtime.config?.period ?? DEFAULT_PERIOD,
        type: ProgressType.Linear,
      })
        .height($r('app.integer.card_progress_height'))
        .color($r('app.color.brand'))
    }
  }
}
