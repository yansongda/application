import { ItemsRuntime } from '../../models/totp/ItemsRuntime';
import { AppPagesName, LogDomain } from '../../App';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TotpCard } from '../TotpCard';

// 首页列表视图（统计条 + 排序提示 + 列表 + 拖拽排序 + 左滑「详情 / 删除」）。
// 自持 ListScroller（左滑项关闭也在组件内完成）；详情 / 删除 / 切换排序态通过 @Event 上报，
// 由页面负责路由跳转、弹窗与接口调用，组件本身不做网络与持久化。
@ComponentV2
export struct TotpListView {
  @Param itemsRuntime: ItemsRuntime = new ItemsRuntime();
  @Param isSortMode: boolean = false;
  @Event onToggleSort: () => void = () => {
  };
  @Event onDetail: (id: string) => void = () => {
  };
  @Event onDelete: (id: string) => void = () => {
  };
  private scroller: ListScroller = new ListScroller();

  build() {
    Column() {
      this.header()

      if (this.isSortMode) {
        this.sortTip()
      }

      this.items()
    }
    .width('100%')
    .height('100%')
  }

  // 排序入口与列表统计放在内容区（与微信小程序一致）：胶囊占据顶部右侧，标题栏不适合再放控件
  @Builder
  header() {
    Row() {
      Text($r('app.string.index_index_page_total', this.itemsRuntime.ids.length))
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('sys.color.font_tertiary'))

      Blank()

      Button(this.isSortMode ? $r('app.string.index_index_page_sort_mode_done') :
        $r('app.string.index_index_page_edit'))
        .type(ButtonType.Normal)
        .height(32)
        .padding({ left: 0, right: 0 })
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.brand'))
        .fontSize($r('app.float.body_font_size'))
        .onClick(() => {
          this.onToggleSort();
        })
    }
    .width('100%')
    .padding({
      left: $r('app.integer.page_padding'),
      right: $r('app.integer.page_padding'),
      top: $r('app.integer.page_padding_smaller'),
      bottom: $r('app.integer.page_padding_smaller')
    })
  }

  @Builder
  sortTip() {
    Row() {
      Text($r('app.string.index_index_page_sort_tip'))
        .fontSize($r('app.float.caption_smaller_font_size'))
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: $r('app.integer.page_padding_smaller') })
  }

  @Builder
  items() {
    List({ scroller: this.scroller }) {
      Repeat<string>(this.itemsRuntime.ids)
        .each((ri: RepeatItem<string>) => {
          ListItem() {
            TotpCard({
              runtime: this.itemsRuntime.get(ri.item.valueOf()),
              isSortMode: this.isSortMode
            })
          }
          .borderRadius($r('app.integer.card_radius'))
          .height($r('app.integer.card_height'))
          .backgroundColor($r('sys.color.background_primary'))
          .swipeAction(this.isSortMode ? undefined : {
            end: {
              builder: () => {
                this.swipeAction(ri.item.valueOf())
              },
            },
            edgeEffect: SwipeEdgeEffect.None,
          })
          .onAttach(() => {
            this.itemsRuntime.start(ri.item.valueOf());
          })
          .onDetach(() => {
            this.itemsRuntime.stop(ri.item.valueOf());
          })
          .onClick(() => {
            if (this.isSortMode) {
              return;
            }

            this.onDetail(ri.item.valueOf());
          })
        })
        // 键值需稳定唯一，拖拽落位动画依赖它（缺省时 Repeat 会生成随机键值）
        .key((id: string): string => id)
        // 拖拽排序由框架接管：仅排序态开启，长按浮起后拖动，离手时在回调中同步数据顺序
        .onMove(this.isSortMode ? (from: number, to: number): void => {
          hilog.info(LogDomain.PAGES, AppPagesName.INDEX, '拖拽排序: %{public}d -> %{public}d', from, to);

          this.itemsRuntime.move(from, to);
        } : undefined)
        .virtualScroll({ totalCount: this.itemsRuntime.ids.length })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  swipeAction(id: string) {
    Row() {
      Button() {
        Text($r("app.string.index_index_page_detail_name"))
          .fontColor($r('sys.color.font_on_primary'))
      }
      .height('100%')
      .width(60)
      .type(ButtonType.Normal)
      .backgroundColor($r('app.color.brand'))
      .onClick(() => {
        this.onDetail(id);

        try {
          this.scroller.closeAllSwipeActions();
        } catch (error) {
          hilog.error(LogDomain.PAGES, AppPagesName.INDEX, '调用 `closeAllSwipeActions` 失败')
        }
      })

      Button() {
        Text($r("app.string.index_index_page_delete_name")).fontColor($r('sys.color.font_on_primary'))
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
}
