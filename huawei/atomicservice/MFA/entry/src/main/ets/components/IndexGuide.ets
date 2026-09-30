const GUIDE_STEPS: number = 4;

// 空数据时的引导页（纯展示组件）：是否展示由父组件决定，跳过/开始通过 onDismiss 上报，添加动作由父组件执行
@ComponentV2
export struct IndexGuide {
  @Event onScan: () => void = () => {
  };
  @Event onInput: () => void = () => {
  };
  @Event onDismiss: () => void = () => {
  };
  @Local
  private guideIndex: number = 0;
  private swiper: SwiperController = new SwiperController();

  build() {
    Column() {
      Swiper(this.swiper) {
        this.guideStep($r('sys.symbol.lock_shield'), $r('app.string.index_guide_page_step_security_title'))
        this.guideActionStep($r('sys.symbol.qrcode'), $r('app.string.index_guide_page_step_scan_title'),
          $r('app.string.index_index_page_add_by_scan'), (): void => {
            this.onScan();
          })
        this.guideActionStep($r('sys.symbol.doc_plaintext_and_pencil'),
          $r('app.string.index_guide_page_step_input_title'),
          $r('app.string.index_index_page_add_by_input'), (): void => {
            this.onInput();
          })
        this.guideStep($r('sys.symbol.checkmark'), $r('app.string.index_guide_page_step_refresh_title'))
      }
      .indicator(new DotIndicator().color($r('sys.color.font_tertiary')).selectedColor($r('app.color.brand')))
      .loop(false)
      .layoutWeight(1)
      .onChange((index: number): void => {
        this.guideIndex = index;
      })

      Row() {
        Button($r('app.string.index_guide_page_skip'))
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.font_secondary'))
          .visibility(this.guideIndex >= GUIDE_STEPS - 1 ? Visibility.None : Visibility.Visible)
          .onClick(() => {
            this.onDismiss();
          })

        Blank()

        Button(this.guideIndex >= GUIDE_STEPS - 1 ? $r('app.string.index_guide_page_start') :
          $r('app.string.index_guide_page_next'))
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('sys.color.font_on_primary'))
          .onClick(() => {
            if (this.guideIndex >= GUIDE_STEPS - 1) {
              this.onDismiss();

              return;
            }

            this.swiper.showNext();
          })
      }
      .width('100%')
      .padding({
        left: $r('app.integer.page_padding'),
        right: $r('app.integer.page_padding'),
        bottom: $r('app.integer.page_padding')
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  guideStep(icon: Resource, title: Resource) {
    Column() {
      Text() {
        SymbolSpan(icon)
      }
      .fontSize($r('app.float.guide_icon_font_size'))
      .fontColor($r('app.color.brand'))

      Text(title)
        .margin({ top: 30 })
        .fontSize($r('app.float.subtitle_font_size'))
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: $r('app.integer.page_padding'), right: $r('app.integer.page_padding') })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  guideActionStep(icon: Resource, title: Resource, actionText: Resource, action: () => void) {
    Column() {
      Text() {
        SymbolSpan(icon)
      }
      .fontSize($r('app.float.guide_icon_font_size'))
      .fontColor($r('app.color.brand'))

      Text(title)
        .margin({ top: 30 })
        .fontSize($r('app.float.subtitle_font_size'))
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)

      Button(actionText)
        .type(ButtonType.Capsule)
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('sys.color.font_on_primary'))
        .margin({ top: 30 })
        .onClick(action)
    }
    .width('100%')
    .height('100%')
    .padding({ left: $r('app.integer.page_padding'), right: $r('app.integer.page_padding') })
    .justifyContent(FlexAlign.Center)
  }
}
