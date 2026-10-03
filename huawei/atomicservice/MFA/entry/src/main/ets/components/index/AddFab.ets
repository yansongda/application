import { SymbolGlyphModifier } from '@kit.ArkUI';

// 首页右下角新增悬浮按钮 + 两种添加入口菜单（扫码 / 手动输入）。
// 可见性由页面控制（空态、排序态不展示），点击结果通过 @Event 上报。
@ComponentV2
export struct AddFab {
  @Event onScan: () => void = () => {
  };
  @Event onInput: () => void = () => {
  };

  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize($r('app.float.fab_icon_font_size'))
        .fontColor([$r('sys.color.font_on_primary')])
    }
    .backgroundColor($r('app.color.brand'))
    .fontColor($r('sys.color.font_on_primary'))
    .padding({
      top: $r('app.integer.page_padding'),
      bottom: $r('app.integer.page_padding'),
      left: $r('app.integer.page_padding'),
      right: $r('app.integer.page_padding')
    })
    .margin({ bottom: $r('app.integer.page_margin'), right: $r('app.integer.page_margin') })
    .bindMenu([
      {
        value: $r('app.string.index_index_page_add_by_scan'),
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.line_viewfinder')),
        action: () => {
          this.onScan();
        },
      },
      {
        value: $r('app.string.index_index_page_add_by_input'),
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.doc_plaintext_and_pencil')),
        action: () => {
          this.onInput();
        },
      }
    ])
  }
}
