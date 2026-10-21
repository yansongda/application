import { Context } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../../App';
import { decodeFilter, encodeFilter, ItemFilterKind, StoredFilter } from '../../utils/ItemFilter';
import { KEY_INDEX_FILTER, KEY_INDEX_GROUPED, Prefs, PrefsInstance } from '../../utils/Prefs';
import { ListViewState } from './ListViewState';

// 首页筛选 / 分组视图的落盘：单库 `mfa` 的 `index.filter`（object：kind + tag）与 `index.grouped`（boolean）。
// 与 ListViewState 分离：状态模型保持纯逻辑（可单测），读写 preferences 只在本文件。
// 搜索词**不落盘**（关闭页面即丢弃）。
const TAG: string = 'models/list_view_state';

export class ListViewStateStore {
  // 冷启动恢复：读不到 / 脏数据一律回落默认视图（「全部 + 平铺」），不影响启动
  static restore(context: Context): ListViewState {
    const state = new ListViewState();
    const prefs: PrefsInstance | undefined = Prefs.open(context);

    if ('undefined' === typeof prefs) {
      return state;
    }

    const decoded = decodeFilter(Prefs.getObject(prefs, KEY_INDEX_FILTER));

    state.filterKind = decoded.kind;
    state.filterTag = decoded.tag;
    // 分组与筛选互斥（见 applyFilter / applyGrouped）：磁盘数据若两者都成立，以筛选为准
    state.isGrouped = Prefs.getBoolean(prefs, KEY_INDEX_GROUPED, false) && ItemFilterKind.ALL === decoded.kind;

    hilog.info(LogDomain.MODELS, TAG, 'restore: kind=%{public}d, tag=%{public}s, grouped=%{public}s',
      state.filterKind, state.filterTag, state.isGrouped.toString());

    return state;
  }

  // 落盘当前筛选与分组。写失败只记日志：视图状态丢失不影响使用
  static save(context: Context, state: ListViewState): boolean {
    const prefs: PrefsInstance | undefined = Prefs.open(context);

    if ('undefined' === typeof prefs) {
      return false;
    }

    const filter: StoredFilter = encodeFilter(state.filterKind, state.filterTag);
    const filterSaved: boolean = Prefs.putObject(prefs, KEY_INDEX_FILTER, filter);
    const groupedSaved: boolean = Prefs.putBoolean(prefs, KEY_INDEX_GROUPED, state.isGrouped);

    if (!filterSaved || !groupedSaved) {
      hilog.error(LogDomain.MODELS, TAG, 'save_failed: filter=%{public}s, grouped=%{public}s',
        filterSaved.toString(), groupedSaved.toString());

      return false;
    }

    return true;
  }

  // 注销账号后清理：筛选/分组是针对被删账号的标签产生的，避免下一个账号继承
  static clear(context: Context): void {
    const prefs: PrefsInstance | undefined = Prefs.open(context);

    if ('undefined' === typeof prefs) {
      return;
    }

    Prefs.deleteKey(prefs, KEY_INDEX_FILTER);
    Prefs.deleteKey(prefs, KEY_INDEX_GROUPED);
  }
}
