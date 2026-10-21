import { describe, expect, it } from '@ohos/hypium';
import { ListViewState } from '../main/ets/models/totp/ListViewState';
import {
  decodeFilter,
  DecodedFilter,
  encodeFilter,
  ItemFilterKind,
  ItemView,
  StoredFilter
} from '../main/ets/utils/ItemFilter';

function view(id: string, tags: string[], pinned: boolean): ItemView {
  return { id: id, issuer: `issuer-${id}`, username: `user-${id}`, tags: tags, pinned: pinned };
}

// 模拟 preferences 里读出来的 `index.filter` 对象（也覆盖「多字段 / 字段缺失」形态）
function stored(kind: string, tag: string): StoredFilter {
  return { kind: kind, tag: tag };
}

export default function listViewStateTest(): void {
  describe('listViewState', () => {
    // 落盘缺失（首次启动）→ 默认视图
    it('decode_missing_returns_all', 0, () => {
      const result: DecodedFilter = decodeFilter(undefined);

      expect(result.kind).assertEqual(ItemFilterKind.ALL);
      expect(result.tag).assertEqual('');
    });

    // 置顶筛选：tag 不参与，避免磁盘残留 tag 影响后续判断
    it('decode_pinned_ignores_tag', 0, () => {
      const result: DecodedFilter = decodeFilter(stored('pinned', '工作'));

      expect(result.kind).assertEqual(ItemFilterKind.PINNED);
      expect(result.tag).assertEqual('');
    });

    // 标签筛选：kind 与 tag 都有效才生效
    it('decode_tag_keeps_tag', 0, () => {
      const result: DecodedFilter = decodeFilter(stored('tag', '工作'));

      expect(result.kind).assertEqual(ItemFilterKind.TAG);
      expect(result.tag).assertEqual('工作');
    });

    // 标签筛选但 tag 为空 → 回落全部（脏数据不能让首页空列表）
    it('decode_tag_without_tag_returns_all', 0, () => {
      const result: DecodedFilter = decodeFilter(stored('tag', ''));

      expect(result.kind).assertEqual(ItemFilterKind.ALL);
      expect(result.tag).assertEqual('');
    });

    // kind 非法（历史版本 / 手改磁盘）→ 回落全部
    it('decode_invalid_kind_returns_all', 0, () => {
      const result: DecodedFilter = decodeFilter(stored('unknown', '工作'));

      expect(result.kind).assertEqual(ItemFilterKind.ALL);
      expect(result.tag).assertEqual('');
    });

    // encode 与 decode 互逆：置顶/全部不带 tag，标签筛选保留 tag
    it('encode_filter_roundtrip', 0, () => {
      const pinned: StoredFilter = encodeFilter(ItemFilterKind.PINNED, '工作');
      const tag: StoredFilter = encodeFilter(ItemFilterKind.TAG, '工作');
      const all: StoredFilter = encodeFilter(ItemFilterKind.ALL, '工作');

      expect(pinned.kind).assertEqual('pinned');
      expect(pinned.tag).assertEqual('');
      expect(tag.tag).assertEqual('工作');
      expect(all.kind).assertEqual('all');
      expect(decodeFilter(tag).kind).assertEqual(ItemFilterKind.TAG);
      expect(decodeFilter(pinned).kind).assertEqual(ItemFilterKind.PINNED);
      expect(decodeFilter(all).kind).assertEqual(ItemFilterKind.ALL);
    });

    // 标签被删空 → 清除筛选并报告「有变更」，供页面回写
    it('sync_view_resets_missing_tag', 0, () => {
      const state = new ListViewState();

      state.applyFilter(ItemFilterKind.TAG, '已删除');

      const changed: boolean = state.syncView([view('1', ['工作'], false)], true);

      expect(changed).assertTrue();
      expect(state.filterKind).assertEqual(ItemFilterKind.ALL);
      expect(state.filterTag).assertEqual('');
    });

    // 筛选仍有效 → 不改状态，也不报告变更（避免每次刷新都写盘）
    it('sync_view_keeps_valid_tag', 0, () => {
      const state = new ListViewState();

      state.applyFilter(ItemFilterKind.TAG, '工作');

      const changed: boolean = state.syncView([view('1', ['工作'], false)], true);

      expect(changed).assertFalse();
      expect(state.filterKind).assertEqual(ItemFilterKind.TAG);
      expect(state.filterTag).assertEqual('工作');
    });

    // 置顶被全部取消 → 回落全部
    it('sync_view_resets_pinned_when_none', 0, () => {
      const state = new ListViewState();

      state.applyFilter(ItemFilterKind.PINNED, '');

      const changed: boolean = state.syncView([view('1', ['工作'], false)], true);

      expect(changed).assertTrue();
      expect(state.filterKind).assertEqual(ItemFilterKind.ALL);
    });

    // 账号被删空 → 清空搜索/筛选/分组
    it('sync_view_clears_on_empty', 0, () => {
      const state = new ListViewState();

      state.query = 'github';
      state.applyFilter(ItemFilterKind.TAG, '工作');

      const changed: boolean = state.syncView([], false);

      expect(changed).assertTrue();
      expect(state.query).assertEqual('');
      expect(state.filterKind).assertEqual(ItemFilterKind.ALL);
      expect(state.isGrouped).assertFalse();
    });
  });
}
