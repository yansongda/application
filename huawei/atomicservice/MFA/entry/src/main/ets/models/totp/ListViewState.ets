import { collectTags, countPinned, ItemFilterKind, ItemView } from '../../utils/ItemFilter';

// 首页列表视图状态：搜索 / 筛选 / 分组。
// **不依赖 ArkUI / preferences**（落盘在 models/totp/ListViewStatePrefs.ets），便于单测；
// 搜索词只影响本地渲染、不持久化；筛选与分组跨进程存活，由页面在变更后显式调用 Prefs 适配层落盘。
// 与 ItemsRuntime 解耦：需要数据快照的判断由调用方传入 ItemView[]，便于单测。
@ObservedV2
export class ListViewState {
  @Trace query: string = '';
  @Trace filterKind: ItemFilterKind = ItemFilterKind.ALL;
  @Trace filterTag: string = '';
  @Trace isGrouped: boolean = false;

  // 筛选与分组互斥：选择筛选即退出分组视图
  applyFilter(kind: ItemFilterKind, tag: string): void {
    this.filterKind = kind;
    this.filterTag = tag;
    this.isGrouped = false;
  }

  // 进入分组视图时清空筛选（分组按标签聚合，叠加筛选会得到空组）
  applyGrouped(grouped: boolean): void {
    this.isGrouped = grouped;

    if (grouped) {
      this.filterKind = ItemFilterKind.ALL;
      this.filterTag = '';
    }
  }

  clearFilter(): void {
    this.query = '';
    this.filterKind = ItemFilterKind.ALL;
    this.filterTag = '';
  }

  // 刷新后清理已失效的视图状态：标签被删空、置顶项被取消时回到默认视图。
  // 分组不需要清理：没有标签时所有条目归入「未分类」，分组入口恒可用。
  // 返回是否发生变更——变更后调用方需要回写，否则下次启动会再加载一遍失效状态。
  // 只比较落盘字段（搜索词不参与：clearFilter 会顺带清 query，但不影响是否需要回写）
  syncView(snapshot: ItemView[]): boolean {
    const kind: ItemFilterKind = this.filterKind;
    const tag: string = this.filterTag;
    const grouped: boolean = this.isGrouped;

    if (snapshot.length === 0) {
      this.clearFilter();
      this.isGrouped = false;
    } else {
      if (this.filterKind === ItemFilterKind.TAG && !collectTags(snapshot).includes(this.filterTag)) {
        this.filterKind = ItemFilterKind.ALL;
        this.filterTag = '';
      }

      if (this.filterKind === ItemFilterKind.PINNED && countPinned(snapshot) === 0) {
        this.filterKind = ItemFilterKind.ALL;
        this.filterTag = '';
      }
    }

    return kind !== this.filterKind || tag !== this.filterTag || grouped !== this.isGrouped;
  }
}
