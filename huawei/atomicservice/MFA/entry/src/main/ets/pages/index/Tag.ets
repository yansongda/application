import { AppStorageV2, KeyboardAvoidMode, LoadingDialogV2 } from '@kit.ArkUI';
import { Totp } from '../../api/Totp';
import { IInfoCardJumpResult } from '../../components/InfoCard';
import { Toast } from '../../utils/PromptAction';

// 标签页路由参数：id + 当前标签 + 账号内已有标签（作为常用标签建议）
export class TagParams {
  id: string;
  tags: string[];
  suggestions: string[];

  constructor(id: string, tags: string[], suggestions: string[]) {
    this.id = id;
    this.tags = [...tags];
    this.suggestions = [...suggestions];
  }
}

class TagChip {
  value: string;
  label: ResourceStr;

  constructor(value: string, label: ResourceStr) {
    this.value = value;
    this.label = label;
  }
}

@Builder
export function builder() {
  Tag()
}

// 标签设置页：预设 + 账号内已有标签 + 自定义输入；保存到服务端（config.tags）。
// 当前 UI 只支持单标签，清除 = 提交空数组；数组结构为后续多标签预留。
@ComponentV2
struct Tag {
  @Local
  private draft: string = '';
  @Local
  private saving: boolean = false;
  private pages: NavPathStack = AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;
  private itemId: string = '';
  @Local
  private suggestions: string[] = [];

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column({ space: $r('app.integer.column_space_smaller') }) {
            TextInput({
              placeholder: $r('app.string.index_tag_page_placeholder'),
              text: this.draft
            })
              .height(44)
              .maxLength(12)
              .defaultFocus(true)
              .backgroundColor($r('sys.color.background_primary'))
              .borderRadius($r('app.integer.card_radius'))
              .onChange((value: string): void => {
                this.draft = value;
              })

            Text($r('app.string.index_tag_page_common'))
              .width('100%')
              .fontSize($r('app.float.caption_smaller_font_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ top: $r('app.integer.page_padding_smaller') })

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.chips(), (chip: TagChip) => {
                Button(chip.label)
                  .type(ButtonType.Capsule)
                  .height(30)
                  .fontSize($r('app.float.caption_smaller_font_size'))
                  .fontColor(this.draft === chip.value ? $r('sys.color.font_on_primary') :
                    $r('sys.color.font_secondary'))
                  .backgroundColor(this.draft === chip.value ? $r('app.color.brand') :
                    $r('sys.color.background_primary'))
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.draft = chip.value;
                  })
              }, (chip: TagChip): string => chip.value)
            }
            .width('100%')

            Text($r('app.string.index_tag_page_note'))
              .width('100%')
              .fontSize($r('app.float.caption_smaller_font_size'))
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)

        Row({ space: $r('app.integer.column_space_smaller') }) {
          if (this.draft.trim().length > 0) {
            Button($r('app.string.index_tag_page_clear'))
              .layoutWeight(1)
              .type(ButtonType.Capsule)
              .height(42)
              .backgroundColor($r('sys.color.background_primary'))
              .fontColor($r('sys.color.font_secondary'))
              .enabled(!this.saving)
              .onClick(() => {
                this.saveTags([]).catch(() => {
                  // 失败已由 Toast 提示，仅避免 unhandled rejection
                });
              })
          }

          Button($r('app.string.index_tag_page_save'))
            .layoutWeight(1)
            .type(ButtonType.Capsule)
            .height(42)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('sys.color.font_on_primary'))
            .enabled(!this.saving)
            .onClick(() => {
              const tag = this.draft.trim();

              this.saveTags(tag.length > 0 ? [tag] : []).catch(() => {
                // 失败已由 Toast 提示，仅避免 unhandled rejection
              });
            })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding({
        left: $r('app.integer.page_padding'),
        right: $r('app.integer.page_padding'),
        top: $r('app.integer.page_margin_smaller'),
        bottom: $r('app.integer.page_padding')
      })
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .title($r('app.string.index_tag_page_title'))
    .onReady((context: NavDestinationContext) => {
      const params = context.pathInfo.param as TagParams | undefined;

      if ('undefined' === typeof params) {
        return;
      }

      this.itemId = params.id;
      this.suggestions = params.suggestions;
      this.draft = params.tags.length > 0 ? params.tags[0] : '';
    })
  }

  @Builder
  loadingDialog() {
    LoadingDialogV2({
      content: $r('app.string.handling'),
    })
  }

  private presetChips(): TagChip[] {
    return [
      new TagChip('工作', $r('app.string.index_tag_page_preset_work')),
      new TagChip('个人', $r('app.string.index_tag_page_preset_personal')),
      new TagChip('财务', $r('app.string.index_tag_page_preset_finance')),
      new TagChip('开发', $r('app.string.index_tag_page_preset_dev')),
      new TagChip('其他', $r('app.string.index_tag_page_preset_other')),
    ];
  }

  private chips(): TagChip[] {
    const chips: TagChip[] = this.presetChips();

    for (const tag of this.suggestions) {
      if (!chips.some((chip: TagChip): boolean => chip.value === tag)) {
        chips.push(new TagChip(tag, tag));
      }
    }

    return chips;
  }

  private async saveTags(tags: string[]): Promise<void> {
    if (this.saving || this.itemId.length === 0) {
      return;
    }

    this.saving = true;

    try {
      await Toast.execute(
        () => Totp.editTags(this.itemId, tags),
        () => this.loadingDialog(),
        $r('app.string.operation_success'),
      );

      this.pages.pop({ value: tags.length > 0 ? tags[0] : '' } as IInfoCardJumpResult);
    } catch (e) {
      // 失败已由 Toast 提示，留在当前页供用户重试
    } finally {
      this.saving = false;
    }
  }
}
