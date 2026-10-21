import { ItemsRuntime } from '../../models/totp/ItemsRuntime';
import { collectTags, countPinned, countTag, ItemFilterKind } from '../../utils/ItemFilter';

// 首页工具条：搜索 + 筛选（视图与筛选合一菜单）+ 排序；排序态退化为提示 + 完成，避免三行头部挤压列表。
// 工具栏状态由页面持有，本组件只做展示与 @Event 上报，不与列表渲染耦合。
@ComponentV2
export struct Toolbar {
  @Param itemsRuntime: ItemsRuntime = new ItemsRuntime();
  @Param isSortMode: boolean = false;
  @Param query: string = '';
  @Param filterKind: ItemFilterKind = ItemFilterKind.ALL;
  @Param filterTag: string = '';
  @Param isGrouped: boolean = false;
  @Event onQueryChange: (query: string) => void = () => {
  };
  @Event onFilterChange: (kind: ItemFilterKind, tag: string) => void = () => {
  };
  @Event onGroupedChange: (grouped: boolean) => void = () => {
  };
  @Event onToggleSort: () => void = () => {
  };

  build() {
    Row({ space: 8 }) {
      if (this.isSortMode) {
        Text($r('app.string.index_index_page_sort_hint'))
          .layoutWeight(1)
          .fontSize($r('app.float.caption_smaller_font_size'))
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(2)

        Button($r('app.string.index_index_page_sort_mode_done'))
          .type(ButtonType.Normal)
          .height(36)
          .padding({ left: 5, right: 5 })
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.tag_text'))
          .fontSize($r('app.float.body_font_size'))
          .onClick(() => {
            this.onToggleSort();
          })
      } else {
        Search({ value: this.query, placeholder: $r('app.string.index_index_page_search_placeholder') })
          .layoutWeight(1)
          .height(36)
          .backgroundColor($r('sys.color.background_primary'))
          .borderRadius(18)
          .onChange((value: string): void => {
            this.onQueryChange(value);
          })

        if (this.hasMeta()) {
          Button(this.filterLabel())
            .type(ButtonType.Normal)
            .height(36)
            .padding({ left: 5, right: 5 })
            .backgroundColor(Color.Transparent)
            .fontColor(this.viewActive() ? $r('app.color.tag_text') : $r('sys.color.font_secondary'))
            .fontSize($r('app.float.body_font_size'))
            .bindMenu(this.filterMenu)
        }

        Button($r('app.string.index_index_page_sort'))
          .type(ButtonType.Normal)
          .height(36)
          .padding({ left: 5, right: 5 })
          .backgroundColor(Color.Transparent)
          .fontColor(this.isSortMode ? $r('app.color.tag_text') : $r('sys.color.font_secondary'))
          .fontSize($r('app.float.body_font_size'))
          .onClick(() => {
            this.onToggleSort();
          })
      }
    }
    .width('100%')
    .padding({
      left: $r('app.integer.page_padding'),
      right: $r('app.integer.page_padding'),
      top: 2,
      bottom: $r('app.integer.page_padding_smaller')
    })
  }

  // 筛选菜单：一个入口承载「视图」与「筛选」，选中项显示对勾
  @Builder
  filterMenu() {
    Menu() {
      MenuItemGroup({ header: $r('app.string.index_index_page_menu_view') }) {
        MenuItem({ content: $r('app.string.index_index_page_view_flat') })
          .selectIcon(true)
          .selected(!this.isGrouped)
          .onClick(() => {
            this.onGroupedChange(false);
          })

        MenuItem({ content: $r('app.string.index_index_page_view_grouped') })
          .selectIcon(true)
          .selected(this.isGrouped)
          .onClick(() => {
            this.onGroupedChange(true);
          })
      }

      MenuItemGroup({ header: $r('app.string.index_index_page_menu_filter') }) {
        MenuItem({ content: $r('app.string.index_index_page_filter_all'), labelInfo: this.itemsRuntime.ids.length.toString() })
          .selectIcon(true)
          .selected(this.filterKind === ItemFilterKind.ALL)
          .labelFont({ size: $r('app.float.caption_font_size') })
          .labelFontColor($r('sys.color.font_tertiary'))
          .onClick(() => {
            this.onFilterChange(ItemFilterKind.ALL, '');
          })

        MenuItem({ content: $r('app.string.index_index_page_filter_pinned'), labelInfo: this.pinnedCount().toString() })
          .selectIcon(true)
          .selected(this.filterKind === ItemFilterKind.PINNED)
          .labelFont({ size: $r('app.float.caption_font_size') })
          .labelFontColor($r('sys.color.font_tertiary'))
          .enabled(this.pinnedCount() > 0)
          .onClick(() => {
            this.onFilterChange(ItemFilterKind.PINNED, '');
          })

        ForEach(this.tagNames(), (tag: string) => {
          MenuItem({ content: tag, labelInfo: this.tagCount(tag).toString() })
            .selectIcon(true)
            .selected(this.filterKind === ItemFilterKind.TAG && this.filterTag === tag)
            .labelFont({ size: $r('app.float.caption_font_size') })
            .labelFontColor($r('sys.color.font_tertiary'))
            .onClick(() => {
              this.onFilterChange(ItemFilterKind.TAG, tag);
            })
        }, (tag: string): string => tag)
      }
    }
    // 菜单默认 16fp / Medium，比列表正文（14fp）偏大；统一为 body_font_size
    .font({ size: $r('app.float.body_font_size') })
  }

  private hasMeta(): boolean {
    return this.itemsRuntime.hasMeta();
  }

  private viewActive(): boolean {
    return this.isGrouped || this.filterKind !== ItemFilterKind.ALL;
  }

  private filterLabel(): ResourceStr {
    if (this.isGrouped) {
      return $r('app.string.index_index_page_view_grouped_short');
    }

    if (this.filterKind === ItemFilterKind.PINNED) {
      return $r('app.string.index_index_page_filter_pinned_short');
    }

    if (this.filterKind === ItemFilterKind.TAG && this.filterTag.length > 0) {
      return `#${this.filterTag}`;
    }

    return $r('app.string.index_index_page_filter');
  }

  private tagNames(): string[] {
    return collectTags(this.itemsRuntime.snapshot());
  }

  private pinnedCount(): number {
    return countPinned(this.itemsRuntime.snapshot());
  }

  private tagCount(tag: string): number {
    return countTag(this.itemsRuntime.snapshot(), tag);
  }
}
