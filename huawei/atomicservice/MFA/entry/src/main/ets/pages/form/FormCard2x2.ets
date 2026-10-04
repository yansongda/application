// 服务卡片（2*2）UI：品牌标题 / 账号数 / 两个添加入口（扫码添加 / 输入添加）。
// 整卡点击打开元服务（列表首页）；两个入口带 mfa_route 直达对应添加流程。
//
// 尺寸约束：官方规格「小卡片 2*2 = 150x150vp」（最小 132vp 宽），四周需留 12vp 安全边距，
// 故内容高度预算约 130vp、宽度约 126vp——字号与间距都按这个预算收紧，新增内容前先核对预算。
//
// 状态管理 V2（ArkTS 卡片自 API 23 起支持）：注入数据按「变量名」匹配，
// 不走 LocalStorage / @LocalStorageProp，@Entry 不传 storage 实例。
// 契约：下列 @Local 变量名必须与 models/form/FormBridge.ets 的 FORM_FIELD_* 常量逐字一致；
//       改名不会编译报错、只会静默不刷新，改一侧必须同步改另一侧。
// 文案只用无参 $r，不用带格式参数的 $r（卡片对格式化的支持未经证实）。
@Entry
@ComponentV2
struct FormCard2x2 {
  // 账号总数（数字字符串，'0' 即空态）
  @Local count: string = '0';

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

  // 有账号：数字与单位说明贴成一组，整组在标题与入口之间居中
  @Builder
  Filled() {
    Column({ space: 2 }) {
      Text(this.count)
        .fontSize($r('app.float.card_number_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.brand'))
        .maxLines(1)

      Text($r('app.string.card_protected_label'))
        .fontSize($r('app.float.card_label_font_size'))
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 空态：两行居中占据同样区间，入口行保持不变
  @Builder
  Empty() {
    Column({ space: 2 }) {
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
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 两个添加入口：等宽（主：扫码添加 / 次：输入添加），各带 mfa_route 直达对应流程
  @Builder
  Actions() {
    Row({ space: 6 }) {
      Text($r('app.string.card_action_scan'))
        .fontSize($r('app.float.card_action_font_size'))
        .fontColor($r('sys.color.font_on_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .padding({ top: 3, bottom: 3 })
        .backgroundColor($r('app.color.brand'))
        .borderRadius($r('app.integer.card_radius'))
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: { mfa_route: 'scan' },
          });
        })

      Text($r('app.string.card_action_input'))
        .fontSize($r('app.float.card_action_font_size'))
        .fontColor($r('app.color.brand'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .padding({ top: 3, bottom: 3 })
        .backgroundColor($r('sys.color.background_secondary'))
        .borderRadius($r('app.integer.card_radius'))
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: { mfa_route: 'input' },
          });
        })
    }
    .width('100%')
  }

  build() {
    Column({ space: 3 }) {
      this.Title()

      Divider()
        .strokeWidth(1)

      // 账号数区吃掉剩余高度，使数字靠上、说明靠底，卡片不留空白
      if ('0' === this.count) {
        this.Empty()
      } else {
        this.Filled()
      }

      // 空态同样保留两个添加入口（正是无账号时最需要的动作）
      this.Actions()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding($r('app.integer.page_padding'))
    // 整卡点击：仅拉起元服务（列表首页），不携带任何参数
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
      });
    })
  }
}
