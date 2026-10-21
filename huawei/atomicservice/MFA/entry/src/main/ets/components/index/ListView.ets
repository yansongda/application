import { ItemsRuntime } from '../../models/totp/ItemsRuntime';
import { ListViewState } from '../../models/totp/ListViewState';
import { AppPagesName, LogDomain } from '../../App';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ListItemCard } from './ListItemCard';
import {
  filterItems,
  groupItems,
  ItemFilterKind,
  ItemGroupKind,
  ItemGroupView,
  ItemView,
  sortPinnedFirst
} from '../../utils/ItemFilter';

// 首页列表视图（平铺/分组列表 + 无匹配占位 + 左滑置顶/删除）。
// 工具条由页面单独编排；自持 ListScroller；详情 / 删除 / 置顶 / 清空筛选通过 @Event 上报，
// 由页面负责路由跳转、接口调用与持久化。
@ComponentV2
export struct ListView {
  @Param itemsRuntime: ItemsRuntime = new ItemsRuntime();
  @Param isSortMode: boolean = false;
  @Param state: ListViewState = new ListViewState();
  @Event onTogglePin: (id: string) => void = () => {
  };
  @Event onDetail: (id: string) => void = () => {
  };
  @Event onDelete: (id: string) => void = () => {
  };
  @Event onClearFilter: () => void = () => {
  };
  private scroller: ListScroller = new ListScroller();

  build() {
    Column() {
      if (this.isNoMatch()) {
        this.noMatch()
      } else {
        this.items()
      }
    }
    .width('100%')
    .height('100%')
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
          this.onClearFilter();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  items() {
    List({ scroller: this.scroller, space: 10 }) {
      if (this.state.isGrouped) {
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
    .height('100%')
    .contentEndOffset(80)
    .sticky(this.state.isGrouped ? StickyStyle.Header : StickyStyle.None)
  }

  @Builder
  listItem(id: string) {
    ListItem() {
      ListItemCard({
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
        .width(80)
        .padding({ left: 4, right: 4 })
        .type(ButtonType.Normal)
        .fontSize($r('app.float.body_font_size'))
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('sys.color.font_on_primary'))
        .onClick(() => {
          this.onTogglePin(id);
          this.closeSwipe();
        })

      Button() {
        Text($r('app.string.index_index_page_delete_name'))
          .fontColor($r('sys.color.font_on_primary'))
          .fontSize($r('app.float.body_font_size'))
      }
      .height('100%')
      .width(64)
      .padding({ left: 4, right: 4 })
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

  private snapshot(): ItemView[] {
    return this.itemsRuntime.snapshot();
  }

  private visibleIds(): string[] {
    const filtered = filterItems(this.snapshot(), this.state.filterKind, this.state.filterTag, this.state.query);
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
    return groupItems(sortPinnedFirst(filterItems(this.snapshot(), this.state.filterKind, this.state.filterTag, this.state.query)));
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
