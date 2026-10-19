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

        // 提供 selectOptions 时渲染下拉单选（如摘要算法），否则维持文本输入
        if ('undefined' !== typeof item.selectOptions) {
          // Select 不设 width 时宽度自适应内容（文字 + 箭头），配合 Blank 贴右，
          // 让选中值紧邻箭头右对齐（Select 本身不支持 textAlign）
          Blank()

          Select(item.selectOptions)
            .selected(item.selectedIndex ?? 0)
            .value(item.value ?? '')
            .backgroundColor($r('sys.color.background_primary'))
            .onSelect((index: number, value: string) => {
              item.selectedIndex = index;
              item.value = value;
              item.callback?.onChange?.(value);
            })
        } else {
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
      .width('100%')
    }
  }
}

@ObservedV2
export class InputCardItem {
  title: ResourceStr;
  placeholder?: ResourceStr;
  @Trace
  value?: ResourceStr;
  // 下拉单选的选项；提供时渲染 Select 而非 TextInput
  selectOptions?: SelectOption[];
  @Trace
  selectedIndex?: number;
  options?: IInputCardItemOptions;
  callback?: IInputCardItemCallback;

  constructor(item: IInputCardItem) {
    this.title = item.title;
    this.placeholder = item.placeholder;
    this.value = item.value;
    this.selectOptions = item.selectOptions;
    this.options = item.options;
    this.callback = item.callback;

    // 选中项跟随 value：每次重建 item（父组件状态变化）时都能恢复到当前值
    if ('undefined' !== typeof item.selectOptions) {
      const index: number = item.selectOptions.findIndex(
        (option: SelectOption): boolean => option.value === item.value);
      this.selectedIndex = index >= 0 ? index : 0;
    }
  }
}

export interface IInputCardItem {
  title: ResourceStr;
  placeholder?: ResourceStr;
  value?: ResourceStr;
  // 提供选项时渲染下拉单选，忽略 options.type / options.maxLength
  selectOptions?: SelectOption[];
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
