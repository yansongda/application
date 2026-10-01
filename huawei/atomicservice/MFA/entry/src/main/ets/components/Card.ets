import { AppStorageV2 } from '@kit.ArkUI';
import { Header } from './Header';

@ComponentV2
export struct Card {
  @Require @Param
  items: CardItem[];
  @Param
  title?: ResourceStr = undefined;
  private pages: NavPathStack = AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;

  build() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      Header({ title: this.title })

      List({ space: 10 }) {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          ForEach(this.items, (item: CardItem) => {
            this.listItem(item)
          }, (item: CardItem, index: number) => index + item.title.toString())
        }
        .divider({ strokeWidth: 1 })
      }
      .width('100%')
      .height(LayoutPolicy.fixAtIdealSize)
    }
  }

  @Builder
  listItem(item: CardItem) {
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
          const result = popInfo.result as IJumpCallbackResult | undefined;

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
          item.callback({ value: result } as IJumpCallbackResult);
        }
      }
    })
  }
}

export interface ICardItemEventClick {
  action: string | CallableFunction;
  params?: object;
}

export interface ICardItem {
  title: ResourceStr;
  value: ResourceStr;
  eventClick?: ICardItemEventClick;
}

@ObservedV2
export class CardItem {
  title: ResourceStr;
  @Trace
  value: ResourceStr;
  eventClick?: ICardItemEventClick;

  constructor(item: ICardItem) {
    this.title = item.title;
    this.value = item.value;
    this.eventClick = item.eventClick;
  }

  callback(result: IJumpCallbackResult) {
    this.value = result.value;
  }
}

export interface IJumpCallbackResult {
  value: string;
}

@ComponentV2
export struct CardInput {
  @Require @Param
  items: CardInputItem[];
  @Param
  title?: ResourceStr = undefined;

  build() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      Header({ title: this.title })

      List({ space: 10 }) {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          ForEach(this.items, (item: CardInputItem) => {
            this.listItem(item)
          }, (item: CardInputItem, index: number) => index + item.title.toString())
        }
        .divider({ strokeWidth: 1 })
      }
      .width('100%')
      .height(LayoutPolicy.fixAtIdealSize)
    }
  }

  @Builder
  listItem(item: CardInputItem) {
    ListItem({ style: ListItemStyle.CARD }) {
      Row() {
        Text(item.title)
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Start)
          .width($r('app.string.components_card_input_item_title_width'))

        TextInput({
          placeholder: item.placeholder,
          text: item.value!!
        })
          .width($r('app.string.components_card_input_item_content_width'))
          .type(item.options?.type ?? InputType.Normal)
          .maxLength(item.options?.maxLength ?? Infinity)
          .textAlign(TextAlign.End)
          .backgroundColor($r('sys.color.background_primary'))
          .onChange((value) => {
            if (item.callback?.onChange) {
              item.callback.onChange(value);
            }
          })
      }
    }
  }
}

@ObservedV2
export class CardInputItem {
  title: ResourceStr;
  placeholder?: ResourceStr;
  @Trace
  value?: ResourceStr;
  options?: ICardInputItemOptions;
  callback?: ICardInputItemCallback;

  constructor(item: ICardInputItem) {
    this.title = item.title;
    this.placeholder = item.placeholder;
    this.value = item.value;
    this.options = item.options;
    this.callback = item.callback;
  }
}

export interface ICardInputItem {
  title: ResourceStr;
  placeholder?: ResourceStr;
  value?: ResourceStr;
  options?: ICardInputItemOptions;
  callback?: ICardInputItemCallback;
}

export interface ICardInputItemOptions {
  type?: InputType;
  maxLength?: number;
}

export interface ICardInputItemCallback {
  onChange?: (value: string) => void;
}
