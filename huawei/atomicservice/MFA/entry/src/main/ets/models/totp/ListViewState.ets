import { collectTags, countPinned, ItemFilterKind, ItemView } from '../../utils/ItemFilter';

// 首页列表视图状态：搜索 / 筛选 / 分组。只影响本地渲染，不落盘、不发请求。
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

  // 刷新后清理已失效的视图状态：标签被删空、置顶项被取消、分组已无意义时回到默认视图
  syncView(snapshot: ItemView[], hasMeta: boolean): void {
    if (snapshot.length === 0) {
      this.clearFilter();
      this.isGrouped = false;

      return;
    }

    if (this.filterKind === ItemFilterKind.TAG && !collectTags(snapshot).includes(this.filterTag)) {
      this.filterKind = ItemFilterKind.ALL;
      this.filterTag = '';
    }

    if (this.filterKind === ItemFilterKind.PINNED && countPinned(snapshot) === 0) {
      this.filterKind = ItemFilterKind.ALL;
      this.filterTag = '';
    }

    if (this.isGrouped && !hasMeta) {
      this.isGrouped = false;
    }
  }
}
