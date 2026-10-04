import { AppStorageV2 } from '@kit.ArkUI';
import { Header } from './Header';

@ComponentV2
export struct InfoCard {
  @Require @Param
  items: InfoCardItem[];
  @Param
  title?: ResourceStr = undefined;
  private pages: NavPathStack = AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;

  build() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      Header({ title: this.title })

      List({ space: 10 }) {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          ForEach(this.items, (item: InfoCardItem) => {
            this.listItem(item)
          }, (item: InfoCardItem, index: number) => index + item.title.toString())
        }
        .divider({ strokeWidth: 1 })
      }
      .width('100%')
      .height(LayoutPolicy.fixAtIdealSize)
    }
  }

  @Builder
  listItem(item: InfoCardItem) {
    ListItem({ style: ListItemStyle.CARD }) {
      Row() {
        Text(item.title)
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Start)
          .width($r('app.string.components_card_input_item_title_width'))

        Row() {
          Text(item.value)
            .textAlign(TextAlign.End)
            .width(item.eventClick ? '90%' : '100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (item.eventClick) {
            Text() {
              SymbolSpan($r('sys.symbol.chevron_right'))
            }
            .textAlign(TextAlign.End)
            .width('10%')
          }
        }
        .width($r('app.string.components_card_input_item_content_width'))
      }
    }
    .onClick(async () => {
      if ('undefined' === typeof item.eventClick) {
        return;
      }

      if ('string' === typeof item.eventClick.action) {
        this.pages.pushPathByName(item.eventClick.action, item.eventClick.params, (popInfo: PopInfo) => {
          // 用户取消弹窗时 result 为空，需判空后再回写，避免类型断言掩盖运行时异常
          const result = popInfo.result as IInfoCardJumpResult | undefined;

          if ('undefined' === typeof result || 'undefined' === typeof result.value) {
            return;
          }

          item.callback(result);
        });
      }

      if ('function' === typeof item.eventClick.action) {
        const result: string | undefined = await item.eventClick.action();

        // 返回 undefined 表示本次操作未产生变更，保持卡片已有显示内容
        if ('undefined' !== typeof result) {
          item.callback({ value: result } as IInfoCardJumpResult);
        }
      }
    })
  }
}

export interface IInfoCardItemEventClick {
  action: string | CallableFunction;
  params?: object;
}

export interface IInfoCardItem {
  title: ResourceStr;
  value: ResourceStr;
  eventClick?: IInfoCardItemEventClick;
}

@ObservedV2
export class InfoCardItem {
  title: ResourceStr;
  @Trace
  value: ResourceStr;
  eventClick?: IInfoCardItemEventClick;

  constructor(item: IInfoCardItem) {
    this.title = item.title;
    this.value = item.value;
    this.eventClick = item.eventClick;
  }

  callback(result: IInfoCardJumpResult) {
    this.value = result.value;
  }
}

export interface IInfoCardJumpResult {
  value: string;
}
