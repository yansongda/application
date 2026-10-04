// 服务卡片（2*2）UI：标题 / 账号数 / 首个账号 / 提示语，
// 整卡点击拉起元服务并请求复制验证码（mfa_action: 'copy'）。
//
// 状态管理 V2（ArkTS 卡片自 API 23 起支持）：注入数据按「变量名」匹配，
// 不再走 LocalStorage / @LocalStorageProp，@Entry 也不传 storage 实例。
// 契约：下列 @Local 变量名必须与 models/card/CardBridge.ets 的 CARD_FIELD_* 常量逐字一致；
//       改名不会编译报错、只会静默不刷新，改一侧必须同步改另一侧。
// 文案只用无参 $r，不用带格式参数的 $r（卡片对格式化的支持未经证实）。
@Entry
@ComponentV2
struct Card {
  // 账号总数（数字字符串，'0' 即空态）
  @Local count: string = '0';

  // 首个账号的发行方（空态为 ''）
  @Local first: string = '';

  // 品牌角标 + 标题
  @Builder
  Title() {
    Row({ space: 5 }) {
      Image($r('app.media.icon'))
        .width(16)
        .height(16)
      Text($r('app.string.card_title'))
        .fontSize($r('app.float.subtitle_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(VerticalAlign.Center)
  }

  // 有账号：数量行（数字强调 + 小号后缀）与首个发行方
  @Builder
  Filled() {
    Row({ space: 2 }) {
      Text(this.count)
        .fontSize($r('app.float.subtitle_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.brand'))
      Text($r('app.string.card_count_suffix'))
        .fontSize($r('app.float.caption_smaller_font_size'))
        .fontColor($r('sys.color.font_secondary'))
    }
    .alignItems(VerticalAlign.Bottom)

    Text(this.first)
      .fontSize($r('app.float.body_font_size'))
      .fontColor($r('sys.color.font_primary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  // 空态：只讲「没有账号」与「怎么加」，不再挂底部提示（空态点卡不复制）
  @Builder
  Empty() {
    Text($r('app.string.card_empty_title'))
      .fontSize($r('app.float.body_font_size'))
      .fontColor($r('sys.color.font_primary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
    Text($r('app.string.card_empty_hint'))
      .fontSize($r('app.float.caption_smaller_font_size'))
      .fontColor($r('sys.color.font_secondary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  build() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      this.Title()

      Divider()
        .strokeWidth(1)

      if ('0' === this.count) {
        this.Empty()
      } else {
        this.Filled()
      }

      // 撑到底：提示语贴底，两态内容节奏一致
      Blank()

      if ('0' !== this.count) {
        Text($r('app.string.card_hint'))
          .fontSize($r('app.float.caption_smaller_font_size'))
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding($r('app.integer.page_padding'))
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { mfa_action: 'copy' },
      });
    })
  }
}
