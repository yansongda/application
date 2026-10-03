// 服务卡片（2*2）完整 UI：标题 / 账号数 / 首个账号 / 提示语 四行布局，
// 整卡点击拉起元服务并请求复制验证码（mfa_action: 'copy'）。
// 数据由 FormExtensionAbility 通过 formBindingData 注入卡片 LocalStorage
// （count / first / hasItems 均为字符串）；文案只用无参 $r，不用带格式参数的 $r。
@Entry
@Component
struct Card {
  @LocalStorageProp('count') count: string = '0';
  @LocalStorageProp('first') first: string = '';
  @LocalStorageProp('hasItems') hasItems: string = '0';

  build() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      Text($r('app.string.card_title'))
        .fontSize($r('app.float.subtitle_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      if (this.hasItems === '1') {
        Row() {
          Text(this.count)
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('sys.color.font_primary'))
          Text($r('app.string.card_count_suffix'))
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('sys.color.font_primary'))
        }
        Text(this.first)
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('sys.color.font_secondary'))
      } else {
        Text($r('app.string.card_empty_title'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('sys.color.font_primary'))
        Text($r('app.string.card_empty_hint'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('sys.color.font_secondary'))
      }
      Text($r('app.string.card_hint'))
        .fontSize($r('app.float.caption_smaller_font_size'))
        .fontColor($r('sys.color.font_secondary'))
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
