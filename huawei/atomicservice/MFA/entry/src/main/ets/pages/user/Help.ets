// 使用帮助页：静态说明，4 个小节（添加账号/使用卡片/多设备同步/安全说明），整页可滚动。
@Builder
export function builder() {
  Help()
}

@ComponentV2
struct Help {
  build() {
    NavDestination() {
      Scroll() {
        Column({ space: $r('app.integer.column_space') }) {
          this.section(
            $r('app.string.user_help_page_add_title'),
            [$r('app.string.user_help_page_add_scan'), $r('app.string.user_help_page_add_input')]
          )
          this.section(
            $r('app.string.user_help_page_card_title'),
            [$r('app.string.user_help_page_card_tip')]
          )
          this.section(
            $r('app.string.user_help_page_sync_title'),
            [$r('app.string.user_help_page_sync_tip')]
          )
          this.section(
            $r('app.string.user_help_page_security_title'),
            [$r('app.string.user_help_page_security_offline'), $r('app.string.user_help_page_security_delete')]
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

  @Builder
  section(title: ResourceStr, texts: ResourceStr[]) {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      Text(title)
        .fontSize($r('app.float.subtitle_font_size'))
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Start)

      ForEach(texts, (text: ResourceStr) => {
        Text(text)
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Start)
      }, (text: ResourceStr, index: number) => index + text.toString())
    }
    .width('100%')
  }
}
