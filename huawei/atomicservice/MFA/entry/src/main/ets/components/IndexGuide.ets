// 空态提示卡（纯展示）：无账号时固定展示 3 条价值要点。
// 图标列宽固定、文字统一左对齐，避免图标宽度不一导致文字起始位置参差。
@ComponentV2
export struct IndexGuide {
  build() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      this.tip($r('sys.symbol.arrow_2_circlepath'), $r('app.string.index_index_page_empty_tip_sync'))
      this.tip($r('sys.symbol.rectangle_on_rectangle'), $r('app.string.index_index_page_empty_tip_card'))
      this.tip($r('sys.symbol.qrcode'), $r('app.string.index_index_page_empty_tip_add'))
    }
    .width('100%')
    .padding($r('app.integer.page_padding'))
    .backgroundColor($r('sys.color.background_primary'))
    .borderRadius($r('app.integer.card_radius'))
    .margin({ top: $r('app.integer.column_space_biggest') })
  }

  // 提示行：图标列固定宽度，文字占满剩余宽度并左对齐（换行时不挤压图标）
  @Builder
  tip(icon: Resource, text: ResourceStr) {
    Row({ space: $r('app.integer.page_padding_smaller') }) {
      Row() {
        SymbolGlyph(icon)
          .fontSize($r('app.float.icon_font_size'))
          .fontColor([$r('app.color.brand')])
      }
      .width(30)
      .justifyContent(FlexAlign.Start)

      Text(text)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Start)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
