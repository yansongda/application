import { AppPagesName, LogDomain } from '../../App';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 首页标题栏（NavDestination title）：头像 + 应用名 + 已保护账号数。
// 纯展示：文案与计数由页面注入，头像点击经 @Event 上报，由页面决定路由。
@ComponentV2
export struct PageTitle {
  @Param avatar: ResourceStr = $r('app.media.default_avatar');
  @Param protectedCount: number = 0;
  @Event onAvatarClick: () => void = () => {
  };

  build() {
    Row() {
      Image(this.avatar)
        .width($r('app.integer.avatar_size'))
        .height($r('app.integer.avatar_size'))
        .autoResize(true)
        .interpolation(ImageInterpolation.Medium)
        .margin({ right: 10 })
        .borderRadius($r('app.integer.card_radius'))
        .onError(() => {
          hilog.warn(LogDomain.PAGES, AppPagesName.INDEX, '头像加载失败，保持当前展示');
        })
        .onClick(() => {
          this.onAvatarClick();
        })

      Column({ space: 2 }) {
        Text($r('app.string.app_name_short'))
          .fontWeight(FontWeight.Bold)
          .fontSize($r('app.float.header_title_font_size'))

        Text($r('app.string.user_detail_page_protected', this.protectedCount))
          .fontSize($r('app.float.header_stat_font_size'))
          .fontColor($r('sys.color.font_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .margin({ left: 10, right: 10 })
    .alignItems(VerticalAlign.Center)
  }
}
