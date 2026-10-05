// 表单输入卡片（InputCard）：与展示型 InfoCard 分文件维护。
import { Header } from './Header';

@ComponentV2
export struct InputCard {
  @Require @Param
  items: InputCardItem[];
  @Param
  title?: ResourceStr = undefined;

  build() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      Header({ title: this.title })

      List({ space: 10 }) {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          ForEach(this.items, (item: InputCardItem) => {
            this.listItem(item)
          }, (item: InputCardItem, index: number) => index + item.title.toString())
        }
        .divider({ strokeWidth: 1 })
      }
      .width('100%')
      .height(LayoutPolicy.fixAtIdealSize)
    }
  }

  @Builder
  listItem(item: InputCardItem) {
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
export class InputCardItem {
  title: ResourceStr;
  placeholder?: ResourceStr;
  @Trace
  value?: ResourceStr;
  options?: IInputCardItemOptions;
  callback?: IInputCardItemCallback;

  constructor(item: IInputCardItem) {
    this.title = item.title;
    this.placeholder = item.placeholder;
    this.value = item.value;
    this.options = item.options;
    this.callback = item.callback;
  }
}

export interface IInputCardItem {
  title: ResourceStr;
  placeholder?: ResourceStr;
  value?: ResourceStr;
  options?: IInputCardItemOptions;
  callback?: IInputCardItemCallback;
}

export interface IInputCardItemOptions {
  type?: InputType;
  maxLength?: number;
}

export interface IInputCardItemCallback {
  onChange?: (value: string) => void;
}
