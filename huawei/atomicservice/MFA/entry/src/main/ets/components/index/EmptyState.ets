import { IndexGuide } from '../IndexGuide';

// 首页空态（纯展示）：英雄区 + 提示卡 + 两个添加主按钮 + 帮助入口。
// 整屏垂直居中，内容高于一屏时自动可滚动；交互全部通过 @Event 上报，由页面决定具体行为。
@ComponentV2
export struct EmptyState {
  @Event onScan: () => void = () => {
  };
  @Event onInput: () => void = () => {
  };
  @Event onHelp: () => void = () => {
  };

  build() {
    Scroll() {
      // 空态整屏垂直居中：内容不足一屏时居中，超过一屏时自动可滚动
      Column() {
        // 英雄区：图标 + 标题 + 一句话价值说明
        Column({ space: $r('app.integer.column_space_smaller') }) {
          SymbolGlyph($r('sys.symbol.lock_shield'))
            .fontSize($r('app.float.empty_icon_font_size'))
            .fontColor([$r('app.color.brand')])

          Text($r('app.string.index_index_page_empty_title'))
            .fontSize($r('app.float.subtitle_font_size'))
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)

          Text($r('app.string.index_index_page_empty_tip_offline'))
            .fontSize($r('app.float.caption_font_size'))
            .fontColor($r('sys.color.font_tertiary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')

        // 空态提示卡：无账号时固定展示
        IndexGuide()

        // 两个并列主按钮：扫码添加 / 手动输入
        Row({ space: $r('app.integer.column_space_smaller') }) {
          Button($r('app.string.index_index_page_add_by_scan'))
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .fontColor($r('sys.color.font_on_primary'))
            .backgroundColor($r('app.color.brand'))
            .onClick(() => {
              this.onScan();
            })

          Button($r('app.string.index_index_page_add_by_input'))
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .fontColor($r('sys.color.font_on_primary'))
            .backgroundColor($r('app.color.brand'))
            .onClick(() => {
              this.onInput();
            })
        }
        .width('100%')
        .margin({ top: $r('app.integer.column_space_biggest') })

        // 次入口：使用帮助
        Button($r('app.string.index_index_page_help_entry'))
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.brand'))
          .fontSize($r('app.float.body_font_size'))
          .margin({ top: $r('app.integer.page_padding_smaller') })
          .onClick(() => {
            this.onHelp();
          })
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .justifyContent(FlexAlign.Center)
      .padding({
        left: $r('app.integer.page_padding'),
        right: $r('app.integer.page_padding'),
        top: $r('app.integer.page_padding'),
        bottom: $r('app.integer.page_padding')
      })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
  }
}
