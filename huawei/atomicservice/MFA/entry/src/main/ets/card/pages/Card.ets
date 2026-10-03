// 服务卡片（2*2）最小 UI：标题 / 账号数 / 首个账号 / 提示语 四行文本，
// 整卡点击拉起元服务并请求复制验证码（mfa_action: 'copy'）。
// 数据由 FormExtensionAbility 通过 formBindingData 注入卡片 LocalStorage，
// 本轮先用默认值渲染，Task 2 补齐真实装配。
@Entry
@Component
struct Card {
  @LocalStorageProp('title') title: string = 'MFA认证';
  @LocalStorageProp('count') count: string = '0';
  @LocalStorageProp('first') first: string = '';
  @LocalStorageProp('hint') hint: string = '点击查看验证码';

  build() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      Text(this.title)
        .fontSize($r('app.float.subtitle_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      Text(this.count)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('sys.color.font_primary'))
      Text(this.first)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('sys.color.font_secondary'))
      Text(this.hint)
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
