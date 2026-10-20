import { DEFAULT_PERIOD, ItemRuntime } from '../models/totp/ItemRuntime';
import { Clipboard } from '../utils/Clipboard';
import { Toast } from '../utils/PromptAction';

// TOTP 列表项卡片内容：发行方/用户名 + 验证码（点击右侧区域即复制）+ 周期进度。
// 右上角叠加「标签 + 置顶」：绝对定位，不参与左右 4:6 布局，验证码字号与居中位置保持不变。
// 注意：ListItem 本体必须留在 List 的直接子节点（拖拽排序 onMove 依赖），这里只承载内容
@ComponentV2
export struct TotpCard {
  @Param runtime: ItemRuntime = ItemRuntime.empty();
  @Param isSortMode: boolean = false;

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
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
            // 7/8 位码比 6 位宽，宽度受限时自动收窄字号，避免被裁切
            Text(this.runtime.code ?? '')
              .fontSize($r('app.float.code_font_size'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .maxFontSize($r('app.float.code_font_size'))
              .minFontSize($r('app.float.code_font_size_min'))
          }
          .layoutWeight(6)
          // 数字即复制入口：点击右侧区域直接复制，不单列复制图标（列表中视觉突兀）
          .onClick(async () => {
            if (this.isSortMode) {
              return;
            }

            const code: string | undefined = this.runtime.code;

            if ('undefined' === typeof code || '' === code) {
              return;
            }

            try {
              await Clipboard.copy(code);

              Toast.show({ message: $r('app.string.index_index_page_copied'), duration: 3000 });
            } catch (e) {
              Toast.show({ message: $r('app.string.index_index_page_copy_failed'), duration: 3000 });
            }
          })
        }
        .height($r('app.integer.card_content_height'))
        .padding({ left: $r('app.integer.page_padding_smaller'), right: $r('app.integer.page_padding_smaller') })

        Progress({
          value: this.runtime.progress ?? DEFAULT_PERIOD,
          total: this.runtime.config?.period ?? DEFAULT_PERIOD,
          type: ProgressType.Linear,
        })
          .height($r('app.integer.card_progress_height'))
          .width('100%')
          .color($r('app.color.brand'))
      }
      .width('100%')

      // 右上角元信息：标签胶囊 + 置顶文字；不拦截卡片点击
      if (this.runtime.tags.length > 0 || this.runtime.pinned) {
        Row({ space: 4 }) {
          if (this.runtime.tags.length > 0) {
            Text(`#${this.runtime.tag}`)
              .fontSize($r('app.float.tag_font_size'))
              .fontColor($r('app.color.tag_text'))
              .backgroundColor($r('app.color.tag_background'))
              .height($r('app.integer.tag_height'))
              .padding({ left: 5, right: 5 })
              .borderRadius(4)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: $r('app.integer.tag_max_width') })
              .maxFontScale(1)
          }

          if (this.runtime.pinned) {
            Text($r('app.string.index_index_page_pin'))
              .fontSize($r('app.float.tag_font_size'))
              .fontColor($r('app.color.tag_text'))
              .fontWeight(FontWeight.Medium)
              .maxFontScale(1)
          }
        }
        .height($r('app.integer.tag_height'))
        .margin({ top: 3, right: 8 })
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
  }
}
