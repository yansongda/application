// 表单输入卡片（CardInput）：与展示型 Card 分文件维护，二者导出与用法均未变。
import { Header } from './Header';

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
