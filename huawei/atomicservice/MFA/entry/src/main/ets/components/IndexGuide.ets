// 首屏引导说明块（纯展示组件）：内嵌在首页空态顶部，紧凑布局不再整屏；点「不再提示」通过 onDismiss 上报，
// 扫码/输入两个添加入口已由空态主按钮承担，不再在本组件内提供
@ComponentV2
export struct IndexGuide {
  @Event onDismiss: () => void = () => {
  };

  build() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      // 区块标题：安全说明（密钥本地计算，不离开设备）
      Row() {
        SymbolGlyph($r('sys.symbol.lock_shield'))
          .fontSize($r('app.float.icon_font_size'))
          .fontColor([$r('app.color.brand')])
        Text($r('app.string.index_guide_page_step_security_title'))
          .fontSize($r('app.float.subtitle_font_size'))
          .fontWeight(FontWeight.Bold)
          .margin({ left: 8 })
      }
      .width('100%')

      // 3 条要点：扫码添加 / 手动输入 / 下拉刷新
      Row() {
        SymbolGlyph($r('sys.symbol.qrcode'))
          .fontSize($r('app.float.icon_font_size'))
          .fontColor([$r('app.color.brand')])
        Text($r('app.string.index_guide_page_step_scan_title'))
          .fontSize($r('app.float.caption_font_size'))
          .margin({ left: 8 })
      }
      .width('100%')

      Row() {
        SymbolGlyph($r('sys.symbol.doc_plaintext_and_pencil'))
          .fontSize($r('app.float.icon_font_size'))
          .fontColor([$r('app.color.brand')])
        Text($r('app.string.index_guide_page_step_input_title'))
          .fontSize($r('app.float.caption_font_size'))
          .margin({ left: 8 })
      }
      .width('100%')

      Row() {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize($r('app.float.icon_font_size'))
          .fontColor([$r('app.color.brand')])
        Text($r('app.string.index_guide_page_step_refresh_title'))
          .fontSize($r('app.float.caption_font_size'))
          .margin({ left: 8 })
      }
      .width('100%')

      // 不再提示：仅隐藏引导块，首屏其余内容保持可见
      Button($r('app.string.index_index_page_guide_dismiss'))
        .type(ButtonType.Capsule)
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('sys.color.font_on_primary'))
        .margin({ top: $r('app.integer.page_padding_smaller') })
        .onClick(() => {
          this.onDismiss();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: $r('app.integer.page_padding'),
      right: $r('app.integer.page_padding'),
      top: $r('app.integer.page_padding'),
      bottom: $r('app.integer.page_padding')
    })
  }
}
