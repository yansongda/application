// 设置型卡片（SettingCard），与展示型 InfoCard / 表单型 InputCard 分文件维护。
// 开关行由模型真值驱动（不做乐观更新）：切换失败时父组件保持模型值不变，
// Toggle 随模型回滚自动复位（技术设计 R7）。
import { Header } from './Header';

export interface ISettingToggle {
  isOn: boolean;
  action: (next: boolean) => void;
}

export interface ISettingItem {
  title: ResourceStr;
  description?: ResourceStr;
  toggle: ISettingToggle;
}

@ComponentV2
export struct SettingCard {
  @Require @Param
  items: ISettingItem[];
  @Param
  title?: ResourceStr = undefined;

  build() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      Header({ title: this.title })

      List({ space: 10 }) {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          ForEach(this.items, (item: ISettingItem) => {
            this.listItem(item)
          }, (item: ISettingItem, index: number) => index + item.title.toString() + item.toggle.isOn.toString())
        }
        .divider({ strokeWidth: 1 })
      }
      .width('100%')
      .height(LayoutPolicy.fixAtIdealSize)
    }
  }

  @Builder
  listItem(item: ISettingItem) {
    ListItem({ style: ListItemStyle.CARD }) {
      Row() {
        Column({ space: 2 }) {
          Text(item.title)
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Start)
            .width('100%')

          if (item.description) {
            Text(item.description)
              .fontSize($r('app.float.caption_smaller_font_size'))
              .fontColor($r('sys.color.font_secondary'))
              .textAlign(TextAlign.Start)
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: item.toggle.isOn })
          .onChange((next: boolean) => {
            item.toggle.action(next);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }
}
