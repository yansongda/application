import { ItemsRuntime } from '../../models/totp/ItemsRuntime';
import { AppPagesName, LogDomain } from '../../App';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TotpCard } from '../TotpCard';
import {
  collectTags,
  countPinned,
  countTag,
  filterItems,
  groupItems,
  ItemFilterKind,
  ItemGroupKind,
  ItemGroupView,
  ItemView,
  sortPinnedFirst
} from '../../utils/ItemFilter';

// 首页列表视图（工具条 + 搜索 + 筛选菜单 + 平铺/分组列表 + 左滑置顶/删除）。
// 自持 ListScroller；详情 / 删除 / 置顶 / 排序 / 筛选通过 @Event 上报，由页面负责路由跳转、接口调用与持久化。
@ComponentV2
export struct TotpListView {
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
  @Event onTogglePin: (id: string) => void = () => {
  };
  @Event onDetail: (id: string) => void = () => {
  };
  @Event onDelete: (id: string) => void = () => {
  };
  private scroller: ListScroller = new ListScroller();

  build() {
    Column() {
      this.listToolbar()

      if (this.isNoMatch()) {
        this.noMatch()
      } else {
        this.items()
      }
    }
    .width('100%')
    .height('100%')
  }

  // 工具条：搜索 + 筛选 + 排序；排序态退化为提示 + 完成，避免三行头部挤压列表
  @Builder
  listToolbar() {
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
          .onClick(() => {
            this.onFilterChange(ItemFilterKind.ALL, '');
          })

        MenuItem({ content: $r('app.string.index_index_page_filter_pinned'), labelInfo: this.pinnedCount().toString() })
          .selectIcon(true)
          .selected(this.filterKind === ItemFilterKind.PINNED)
          .enabled(this.pinnedCount() > 0)
          .onClick(() => {
            this.onFilterChange(ItemFilterKind.PINNED, '');
          })

        ForEach(this.tagNames(), (tag: string) => {
          MenuItem({ content: tag, labelInfo: this.tagCount(tag).toString() })
            .selectIcon(true)
            .selected(this.filterKind === ItemFilterKind.TAG && this.filterTag === tag)
            .onClick(() => {
              this.onFilterChange(ItemFilterKind.TAG, tag);
            })
        }, (tag: string): string => tag)
      }
    }
  }

  // 无匹配结果：只占列表区域，不显示全屏空态
  @Builder
  noMatch() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      Text($r('app.string.index_index_page_no_match'))
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('sys.color.font_tertiary'))

      Button($r('app.string.index_index_page_clear_filter'))
        .type(ButtonType.Capsule)
        .backgroundColor($r('sys.color.background_primary'))
        .fontColor($r('app.color.tag_text'))
        .fontSize($r('app.float.caption_font_size'))
        .onClick(() => {
          this.onQueryChange('');
          this.onFilterChange(ItemFilterKind.ALL, '');
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  items() {
    List({ scroller: this.scroller, space: 10 }) {
      if (this.isGrouped) {
        ForEach(this.groups(), (group: ItemGroupView) => {
          ListItemGroup({ header: this.groupHeader(group), space: 10 }) {
            ForEach(group.ids, (id: string) => {
              this.listItem(id)
            }, (id: string): string => id)
          }
        }, (group: ItemGroupView): string => `${group.kind}:${group.tag}`)
      } else {
        Repeat<string>(this.visibleIds())
          .each((ri: RepeatItem<string>) => {
            this.listItem(ri.item.valueOf())
          })
          // 键值需稳定唯一，拖拽落位动画依赖它（缺省时 Repeat 会生成随机键值）
          .key((id: string): string => id)
          // 拖拽排序由框架接管：仅排序态开启，长按浮起后拖动，离手时在回调中同步数据顺序
          .onMove(this.isSortMode ? (from: number, to: number): void => {
            hilog.info(LogDomain.PAGES, AppPagesName.INDEX, '拖拽排序: %{public}d -> %{public}d', from, to);

            this.itemsRuntime.move(from, to);
          } : undefined)
          .virtualScroll({ totalCount: this.visibleIds().length })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .sticky(this.isGrouped ? StickyStyle.Header : StickyStyle.None)
  }

  @Builder
  listItem(id: string) {
    ListItem() {
      TotpCard({
        runtime: this.itemsRuntime.get(id),
        isSortMode: this.isSortMode
      })
    }
    .borderRadius($r('app.integer.card_radius'))
    .height($r('app.integer.card_height'))
    .backgroundColor($r('sys.color.background_primary'))
    .swipeAction(this.isSortMode ? undefined : {
      end: {
        builder: () => {
          this.swipeAction(id)
        },
      },
      edgeEffect: SwipeEdgeEffect.None,
    })
    .onAttach(() => {
      this.itemsRuntime.start(id);
    })
    .onDetach(() => {
      this.itemsRuntime.stop(id);
    })
    .onClick(() => {
      if (this.isSortMode) {
        return;
      }

      this.onDetail(id);
    })
  }

  @Builder
  groupHeader(group: ItemGroupView) {
    Row() {
      Text(this.groupTitle(group))
        .fontSize($r('app.float.caption_smaller_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_secondary'))

      Blank()

      Text(group.ids.length.toString())
        .fontSize($r('app.float.caption_smaller_font_size'))
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 4, bottom: 2 })
    .backgroundColor($r('sys.color.background_secondary'))
  }

  @Builder
  swipeAction(id: string) {
    Row() {
      Button(this.itemsRuntime.get(id).pinned ? $r('app.string.index_index_page_unpin') :
        $r('app.string.index_index_page_pin'))
        .height('100%')
        .width(70)
        .type(ButtonType.Normal)
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('sys.color.font_on_primary'))
        .onClick(() => {
          this.onTogglePin(id);
          this.closeSwipe();
        })

      Button() {
        Text($r('app.string.index_index_page_delete_name'))
          .fontColor($r('sys.color.font_on_primary'))
      }
      .height('100%')
      .width(60)
      .type(ButtonType.Normal)
      .backgroundColor($r('sys.color.warning'))
      .onClick(() => {
        this.onDelete(id);
      })
    }
  }

  private closeSwipe(): void {
    try {
      this.scroller.closeAllSwipeActions();
    } catch (error) {
      hilog.error(LogDomain.PAGES, AppPagesName.INDEX, '调用 `closeAllSwipeActions` 失败');
    }
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

  private snapshot(): ItemView[] {
    return this.itemsRuntime.snapshot();
  }

  private visibleIds(): string[] {
    const filtered = filterItems(this.snapshot(), this.filterKind, this.filterTag, this.query);
    const ordered = this.isSortMode ? filtered : sortPinnedFirst(filtered);
    const ids: string[] = [];

    for (const item of ordered) {
      ids.push(item.id);
    }

    return ids;
  }

  private isNoMatch(): boolean {
    return this.itemsRuntime.ids.length > 0 && this.visibleIds().length === 0;
  }

  private groups(): ItemGroupView[] {
    return groupItems(sortPinnedFirst(filterItems(this.snapshot(), this.filterKind, this.filterTag, this.query)));
  }

  private tagNames(): string[] {
    return collectTags(this.snapshot());
  }

  private pinnedCount(): number {
    return countPinned(this.snapshot());
  }

  private tagCount(tag: string): number {
    return countTag(this.snapshot(), tag);
  }

  private groupTitle(group: ItemGroupView): ResourceStr {
    if (group.kind === ItemGroupKind.PINNED) {
      return $r('app.string.index_index_page_pin');
    }

    if (group.kind === ItemGroupKind.UNASSIGNED) {
      return $r('app.string.index_index_page_unassigned');
    }

    return group.tag;
  }
}
