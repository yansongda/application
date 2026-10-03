// 使用帮助页：静态说明，4 个小节（添加账号/使用卡片/多设备同步/安全说明），每节一张白底圆角卡片，整页可滚动。
@Builder
export function builder() {
  Help()
}

@ComponentV2
struct Help {
  build() {
    NavDestination() {
      Scroll() {
        Column({ space: $r('app.integer.column_space_smaller') }) {
          this.section(
            $r('sys.symbol.qrcode'),
            $r('app.string.user_help_page_add_title'),
            [$r('app.string.user_help_page_add_scan'), $r('app.string.user_help_page_add_input')]
          )
          this.section(
            $r('sys.symbol.rectangle_on_rectangle'),
            $r('app.string.user_help_page_card_title'),
            [$r('app.string.user_help_page_card_tip'), $r('app.string.user_help_page_card_copy')]
          )
          this.section(
            $r('sys.symbol.arrow_2_circlepath'),
            $r('app.string.user_help_page_sync_title'),
            [$r('app.string.user_help_page_sync_tip')]
          )
          this.section(
            $r('sys.symbol.lock_shield'),
            $r('app.string.user_help_page_security_title'),
            [
              $r('app.string.user_help_page_security_offline'),
              $r('app.string.user_help_page_security_swipe_delete'),
              $r('app.string.user_help_page_security_delete')
            ]
          )
        }
        .width('100%')
        .padding($r('app.integer.page_padding'))
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .title($r('app.string.user_help_page_title'))
  }

  // 小节卡片：品牌图标列（定宽）+ 标题 + 说明行。图标列定宽，标题与说明文字的左边缘自然对齐，
  // 不依赖魔法缩进；说明文字用 font_secondary，保证长句在卡片内的可读性。
  @Builder
  section(icon: Resource, title: ResourceStr, texts: ResourceStr[]) {
    Row({ space: $r('app.integer.page_padding_smaller') }) {
      Row() {
        SymbolGlyph(icon)
          .fontSize($r('app.float.icon_font_size'))
          .fontColor([$r('app.color.brand')])
      }
      .width(30)
      .justifyContent(FlexAlign.Start)

      Column({ space: $r('app.integer.column_space_smaller') }) {
        Text(title)
          .fontSize($r('app.float.body_font_size'))
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Start)
          .width('100%')

        Column({ space: $r('app.integer.page_padding_smaller') }) {
          ForEach(texts, (text: ResourceStr) => {
            Text(text)
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('sys.color.font_secondary'))
              .textAlign(TextAlign.Start)
              .width('100%')
          }, (text: ResourceStr, index: number) => index + text.toString())
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding($r('app.integer.page_padding'))
    .backgroundColor($r('sys.color.background_primary'))
    .borderRadius($r('app.integer.card_radius'))
  }
}
