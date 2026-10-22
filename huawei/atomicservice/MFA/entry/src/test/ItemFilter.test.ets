import { describe, expect, it } from '@ohos/hypium';
import {
  collectTags,
  collectTagStats,
  countPinned,
  countTag,
  filterItems,
  groupItems,
  ItemFilterKind,
  ItemGroupKind,
  ItemGroupView,
  ItemView,
  sortPinnedFirst,
  TagStat
} from '../main/ets/utils/ItemFilter';

function view(id: string, issuer: string, username: string, tags: string[], pinned: boolean): ItemView {
  return { id: id, issuer: issuer, username: username, tags: tags, pinned: pinned };
}

function idsOf(items: ItemView[]): string[] {
  const ids: string[] = [];

  for (const item of items) {
    ids.push(item.id);
  }

  return ids;
}

export default function itemFilterTest(): void {
  describe('itemFilter', () => {
    const all: ItemView[] = [
      view('1', 'GitHub', 'alice@example.com', ['工作'], true),
      view('2', 'GitLab', 'bob@example.com', ['开发'], false),
      view('3', '阿里云', 'alice', [], false),
      view('4', 'Google', 'alice@gmail.com', ['个人'], false),
      view('5', '腾讯云', 'alice', ['工作'], false),
    ];

    it('filter_all_returns_all', 0, () => {
      const result = filterItems(all, ItemFilterKind.ALL, '', '');

      expect(JSON.stringify(idsOf(result))).assertEqual(JSON.stringify(['1', '2', '3', '4', '5']));
    });

    it('filter_query_matches_issuer_username_and_tag_case_insensitive', 0, () => {
      expect(JSON.stringify(idsOf(filterItems(all, ItemFilterKind.ALL, '', 'github'))))
        .assertEqual(JSON.stringify(['1']));
      expect(JSON.stringify(idsOf(filterItems(all, ItemFilterKind.ALL, '', 'BOB@EXAMPLE'))))
        .assertEqual(JSON.stringify(['2']));
      expect(JSON.stringify(idsOf(filterItems(all, ItemFilterKind.ALL, '', '工作'))))
        .assertEqual(JSON.stringify(['1', '5']));
    });

    it('filter_query_multiple_tokens_are_and', 0, () => {
      expect(JSON.stringify(idsOf(filterItems(all, ItemFilterKind.ALL, '', 'alice 工作'))))
        .assertEqual(JSON.stringify(['1', '5']));
      expect(JSON.stringify(idsOf(filterItems(all, ItemFilterKind.ALL, '', 'alice 开发'))))
        .assertEqual(JSON.stringify([]));
    });

    it('filter_pinned_and_tag', 0, () => {
      expect(JSON.stringify(idsOf(filterItems(all, ItemFilterKind.PINNED, '', ''))))
        .assertEqual(JSON.stringify(['1']));
      expect(JSON.stringify(idsOf(filterItems(all, ItemFilterKind.TAG, '工作', ''))))
        .assertEqual(JSON.stringify(['1', '5']));
    });

    it('sort_pinned_first_is_stable', 0, () => {
      const result = sortPinnedFirst(all);

      expect(JSON.stringify(idsOf(result))).assertEqual(JSON.stringify(['1', '2', '3', '4', '5']));

      const reordered = sortPinnedFirst([all[1], all[0], all[4], all[2]]);

      expect(JSON.stringify(idsOf(reordered))).assertEqual(JSON.stringify(['1', '2', '5', '3']));
    });

    it('group_pinned_then_tags_then_unassigned', 0, () => {
      const groups = groupItems(sortPinnedFirst(all));
      const summary = groups.map((group: ItemGroupView): string => `${group.kind}:${group.tag}:${group.ids.join(',')}`);

      // 置顶项只进置顶组，不再进入「工作」组
      expect(JSON.stringify(summary)).assertEqual(JSON.stringify([
        '0::1',
        '1:开发:2',
        '1:个人:4',
        '1:工作:5',
        '2::3',
      ]));
      expect(groups[0].kind).assertEqual(ItemGroupKind.PINNED);
    });

    it('collect_tags_dedupes_in_first_seen_order', 0, () => {
      expect(JSON.stringify(collectTags(all))).assertEqual(JSON.stringify(['工作', '开发', '个人']));
    });

    it('count_tag_and_pinned', 0, () => {
      expect(countTag(all, '工作')).assertEqual(2);
      expect(countTag(all, '不存在')).assertEqual(0);
      expect(countPinned(all)).assertEqual(1);
    });

    // 菜单用的一次性聚合：顺序与 collectTags 一致、计数与 countTag 一致
    it('collect_tag_stats_matches_collect_tags_and_count_tag', 0, () => {
      const stats: TagStat[] = collectTagStats(all);

      expect(stats.length).assertEqual(3);
      expect(stats[0].tag).assertEqual('工作');
      expect(stats[0].count).assertEqual(2);
      expect(stats[1].tag).assertEqual('开发');
      expect(stats[1].count).assertEqual(1);
      expect(stats[2].tag).assertEqual('个人');
      expect(stats[2].count).assertEqual(1);

      for (const stat of stats) {
        expect(stat.count).assertEqual(countTag(all, stat.tag));
      }
    });

    // 同一 item 内重复标签只计一次、空标签忽略（与 countTag / collectTags 语义一致）
    it('collect_tag_stats_dedupes_within_item', 0, () => {
      const stats: TagStat[] = collectTagStats([
        view('1', 'A', 'a', ['工作', '工作', ''], false),
        view('2', 'B', 'b', ['工作'], false),
      ]);

      expect(stats.length).assertEqual(1);
      expect(stats[0].tag).assertEqual('工作');
      expect(stats[0].count).assertEqual(2);
    });
  });
}
