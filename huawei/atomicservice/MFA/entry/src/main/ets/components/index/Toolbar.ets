import { ItemsRuntime } from '../../models/totp/ItemsRuntime';
import { ListViewState } from '../../models/totp/ListViewState';
import { collectTags, countPinned, countTag, ItemFilterKind } from '../../utils/ItemFilter';

// 首页工具条：搜索 + 筛选（视图与筛选合一菜单）+ 排序；排序态退化为提示 + 完成，避免三行头部挤压列表。
// 工具栏状态由页面持有，本组件只做展示与 @Event 上报，不与列表渲染耦合。
@ComponentV2
export struct Toolbar {
  @Param itemsRuntime: ItemsRuntime = new ItemsRuntime();
  @Param isSortMode: boolean = false;
  @Param state: ListViewState = new ListViewState();
  // 筛选菜单显隐（bindMenu 的 isShow 形态，内容自绘）：系统 Menu 的菜单项行高固定（约 48vp）、
  // 分组标题没有字体属性，做不出设计稿的「标题小字 + 紧凑行高」层级
  @Local private isMenuShow: boolean = false;
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
        Search({ value: this.state.query, placeholder: $r('app.string.index_index_page_search_placeholder') })
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
            .bindMenu(this.isMenuShow, this.filterMenuContent, {
              // 点菜单外区域由系统关闭；这里复位状态，否则下次点击会被当成「已展开」而打不开
              onDisappear: (): void => {
                this.isMenuShow = false;
              },
            })
            .onClick((): void => {
              this.isMenuShow = true;
            })
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

  // 筛选菜单（视图 + 筛选合一）：结构对齐设计稿
  // design: docs/2026-10-20-huawei-mfa-search-tag-pin-ui-preview.html
  // 弹层容器（背景 / 圆角 / 阴影 / 点外关闭 / 进出动效）仍由系统菜单提供，这里只自绘内容
  @Builder
  filterMenuContent() {
    Column() {
      this.menuSection($r('app.string.index_index_page_menu_view'))

      this.menuOption($r('app.string.index_index_page_view_flat'), '', !this.state.isGrouped, true,
        (): void => {
          this.onGroupedChange(false);
        })

      this.menuOption($r('app.string.index_index_page_view_grouped'), '', this.state.isGrouped, true,
        (): void => {
          this.onGroupedChange(true);
        })

      this.menuDivider()

      this.menuSection($r('app.string.index_index_page_menu_filter'))

      this.menuOption($r('app.string.index_index_page_filter_all'), this.itemsRuntime.ids.length.toString(),
        this.state.filterKind === ItemFilterKind.ALL, true, (): void => {
          this.onFilterChange(ItemFilterKind.ALL, '');
        })

      this.menuOption($r('app.string.index_index_page_filter_pinned'), this.pinnedCount().toString(),
        this.state.filterKind === ItemFilterKind.PINNED, this.pinnedCount() > 0, (): void => {
          this.onFilterChange(ItemFilterKind.PINNED, '');
        })

      ForEach(this.tagNames(), (tag: string) => {
        this.menuOption(tag, this.tagCount(tag).toString(),
          this.state.filterKind === ItemFilterKind.TAG && this.state.filterTag === tag, true, (): void => {
            this.onFilterChange(ItemFilterKind.TAG, tag);
          })
      }, (tag: string): string => tag)
    }
    .width(218)
    .padding({ top: 5, bottom: 5 })
    .alignItems(HorizontalAlign.Start)
  }

  // 分组标题：设计稿 10px 在真机偏小（系统字体放大后更甚），取最小可读档 12fp + 三级色，
  // 与 14fp 正文形成「标题 / 选项 / 计数」三级层级
  @Builder
  menuSection(title: ResourceStr) {
    Text(title)
      .width('100%')
      .height(26)
      .padding({ left: 14, right: 14 })
      .fontSize($r('app.float.caption_smaller_font_size'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_tertiary'))
  }

  // 选项行：对勾槽位固定 18vp（选中/未选中文字不左右跳动）；数量右对齐小字；行高 36vp
  @Builder
  menuOption(content: ResourceStr, count: string, selected: boolean, selectable: boolean, action: () => void) {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.checkmark'))
        .width(18)
        .fontSize(16)
        .fontColor([$r('app.color.tag_text')])
        .visibility(selected ? Visibility.Visible : Visibility.Hidden)

      Text(content)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontSize($r('app.float.body_font_size'))
        .fontColor(selected ? $r('app.color.tag_text') : $r('sys.color.font_primary'))

      if (count.length > 0) {
        Text(count)
          .fontSize($r('app.float.caption_smaller_font_size'))
          .fontColor($r('sys.color.font_tertiary'))
      }
    }
    .width('100%')
    .height(36)
    .padding({ left: 14, right: 14 })
    .enabled(selectable)
    .opacity(selectable ? 1 : 0.4)
    .onClick((): void => {
      action();
      this.isMenuShow = false;
    })
  }

  @Builder
  menuDivider() {
    Divider()
      .strokeWidth(0.5)
      .margin({ top: 5, bottom: 5 })
  }

  private hasMeta(): boolean {
    return this.itemsRuntime.hasMeta();
  }

  private viewActive(): boolean {
    return this.state.isGrouped || this.state.filterKind !== ItemFilterKind.ALL;
  }

  private filterLabel(): ResourceStr {
    if (this.state.isGrouped) {
      return $r('app.string.index_index_page_view_grouped_short');
    }

    if (this.state.filterKind === ItemFilterKind.PINNED) {
      return $r('app.string.index_index_page_filter_pinned_short');
    }

    if (this.state.filterKind === ItemFilterKind.TAG && this.state.filterTag.length > 0) {
      return `#${this.state.filterTag}`;
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
