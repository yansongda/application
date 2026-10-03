// 空态提示卡（纯展示组件）：3 条价值要点 + 弱化的「不再提示」文本按钮。
// 图标列宽固定、文字统一左对齐，避免图标宽度不一导致文字起始位置参差；
// 点「不再提示」通过 onDismiss 上报，由页面持久化标记，之后空态不再展示本卡。
@ComponentV2
export struct IndexGuide {
  @Event onDismiss: () => void = () => {
  };

  build() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      Column({ space: $r('app.integer.column_space_smaller') }) {
        this.tip($r('sys.symbol.arrow_2_circlepath'), $r('app.string.index_index_page_empty_tip_sync'))
        this.tip($r('sys.symbol.rectangle_on_rectangle'), $r('app.string.index_index_page_empty_tip_card'))
        this.tip($r('sys.symbol.qrcode'), $r('app.string.index_index_page_empty_tip_add'))
      }
      .width('100%')
      .padding($r('app.integer.page_padding'))
      .backgroundColor($r('sys.color.background_primary'))
      .borderRadius($r('app.integer.card_radius'))

      // 次入口：仅隐藏本卡，空态英雄区与添加按钮保持可见
      Button($r('app.string.index_index_page_guide_dismiss'))
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .fontColor($r('sys.color.font_tertiary'))
        .fontSize($r('app.float.caption_smaller_font_size'))
        .padding({ left: 0, right: 0 })
        .onClick(() => {
          this.onDismiss();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
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
