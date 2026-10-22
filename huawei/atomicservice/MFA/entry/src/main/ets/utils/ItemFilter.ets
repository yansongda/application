// 首页搜索 / 筛选 / 置顶排序 / 分组的纯函数集合。
// 不依赖 ArkUI / 网络 / preferences，便于在 entry/src/test 下直接单测。
// 搜索为本地全量过滤：数据量级为个位数到几十，无需服务端接口。

export enum ItemFilterKind {
  ALL = 0,
  PINNED = 1,
  TAG = 2,
}

export enum ItemGroupKind {
  PINNED = 0,
  TAG = 1,
  UNASSIGNED = 2,
}

export interface ItemView {
  id: string;
  issuer: string;
  username: string;
  tags: string[];
  pinned: boolean;
}

export interface ItemGroupView {
  kind: ItemGroupKind;
  tag: string;
  ids: string[];
}

// 落盘的 kind 取值：用字符串而非枚举数字（磁盘数据可读，增删枚举不会串值）
const KIND_ALL: string = 'all';
const KIND_PINNED: string = 'pinned';
const KIND_TAG: string = 'tag';

// preferences 中 `index.filter` 的存储结构：kind 与 tag 语义耦合（tag 仅在 kind=tag 时有意义），
// 所以两者必须同一个 key 原子写入，避免出现「kind 已改、tag 还是旧值」的中间态
export interface StoredFilter {
  kind: string;
  tag: string;
}

export interface DecodedFilter {
  kind: ItemFilterKind;
  tag: string;
}

// 生效筛选 → 磁盘结构（搜索词不参与持久化）
export function encodeFilter(kind: ItemFilterKind, tag: string): StoredFilter {
  if (ItemFilterKind.PINNED === kind) {
    return { kind: KIND_PINNED, tag: '' };
  }

  if (ItemFilterKind.TAG === kind) {
    return { kind: KIND_TAG, tag: tag };
  }

  return { kind: KIND_ALL, tag: '' };
}

// 磁盘结构 → 生效筛选：kind 非法 / tag 为空 / 类型不符一律回落「全部」（脏数据不能让首页空列表）
export function decodeFilter(raw: object | undefined): DecodedFilter {
  if ('undefined' === typeof raw) {
    return { kind: ItemFilterKind.ALL, tag: '' };
  }

  const stored: StoredFilter = raw as StoredFilter;
  const tag: string = 'string' === typeof stored.tag ? stored.tag : '';

  if (KIND_PINNED === stored.kind) {
    return { kind: ItemFilterKind.PINNED, tag: '' };
  }

  if (KIND_TAG === stored.kind && tag.length > 0) {
    return { kind: ItemFilterKind.TAG, tag: tag };
  }

  return { kind: ItemFilterKind.ALL, tag: '' };
}

// 冷启动要恢复的完整视图（含分组开关）：与落盘结构合并后的最终形态
export interface StoredView {
  kind: ItemFilterKind;
  tag: string;
  isGrouped: boolean;
}

// 磁盘结构 + 分组开关 → 生效视图。
// 分组与筛选互斥（见 ListViewState.applyFilter / applyGrouped）：磁盘数据若两者都成立，以筛选为准
// （否则会渲染出「分组视图 + 标签筛选」这种组合，得到空组）
export function decodeView(raw: object | undefined, grouped: boolean): StoredView {
  const decoded: DecodedFilter = decodeFilter(raw);

  return {
    kind: decoded.kind,
    tag: decoded.tag,
    isGrouped: grouped && ItemFilterKind.ALL === decoded.kind,
  };
}

// 搜索分词：按空白拆分、归一化为小写；空串表示不过滤
function queryTokens(query: string): string[] {
  const tokens: string[] = [];

  for (const raw of query.trim().split(' ')) {
    const token = raw.trim().toLocaleLowerCase();

    if (token.length > 0) {
      tokens.push(token);
    }
  }

  return tokens;
}

// 多个词之间为 AND：每个词命中发行方 / 用户名 / 任一标签即可
function matchesQuery(item: ItemView, tokens: string[]): boolean {
  if (tokens.length === 0) {
    return true;
  }

  const fields: string[] = [item.issuer, item.username];

  for (const tag of item.tags) {
    fields.push(tag);
  }

  for (const token of tokens) {
    let hit = false;

    for (const field of fields) {
      if (field.toLocaleLowerCase().includes(token)) {
        hit = true;
        break;
      }
    }

    if (!hit) {
      return false;
    }
  }

  return true;
}

export function filterItems(items: ItemView[], kind: ItemFilterKind, tag: string, query: string): ItemView[] {
  const tokens = queryTokens(query);
  const result: ItemView[] = [];

  for (const item of items) {
    if (kind === ItemFilterKind.PINNED && !item.pinned) {
      continue;
    }

    if (kind === ItemFilterKind.TAG && !item.tags.includes(tag)) {
      continue;
    }

    if (matchesQuery(item, tokens)) {
      result.push(item);
    }
  }

  return result;
}

// 稳定分区：置顶项保持原有相对顺序，非置顶项保持原有相对顺序
export function sortPinnedFirst(items: ItemView[]): ItemView[] {
  const pinned: ItemView[] = [];
  const rest: ItemView[] = [];

  for (const item of items) {
    if (item.pinned) {
      pinned.push(item);
    } else {
      rest.push(item);
    }
  }

  return pinned.concat(rest);
}

// 分区视图：置顶 → 各标签（按首次出现顺序）→ 未分类。
// 置顶项只出现在置顶组，不再进入标签组，避免同一账号渲染两次（重复定时器）。
export function groupItems(items: ItemView[]): ItemGroupView[] {
  const pinned: string[] = [];
  const tagOrder: string[] = [];
  const tagIds: Map<string, string[]> = new Map();
  const unassigned: string[] = [];

  for (const item of items) {
    if (item.pinned) {
      pinned.push(item.id);
      continue;
    }

    const tag = item.tags.length > 0 ? item.tags[0] : '';

    if (tag.length === 0) {
      unassigned.push(item.id);
      continue;
    }

    if (!tagIds.has(tag)) {
      tagIds.set(tag, []);
      tagOrder.push(tag);
    }

    const ids = tagIds.get(tag);

    if ('undefined' !== typeof ids) {
      ids.push(item.id);
    }
  }

  const groups: ItemGroupView[] = [];

  if (pinned.length > 0) {
    groups.push({ kind: ItemGroupKind.PINNED, tag: '', ids: pinned });
  }

  for (const tag of tagOrder) {
    const ids = tagIds.get(tag);

    if ('undefined' !== typeof ids && ids.length > 0) {
      groups.push({ kind: ItemGroupKind.TAG, tag: tag, ids: ids });
    }
  }

  if (unassigned.length > 0) {
    groups.push({ kind: ItemGroupKind.UNASSIGNED, tag: '', ids: unassigned });
  }

  return groups;
}

// 标签列表：按首次出现顺序去重，空标签忽略
export function collectTags(items: ItemView[]): string[] {
  const tags: string[] = [];

  for (const item of items) {
    for (const tag of item.tags) {
      if (tag.length > 0 && !tags.includes(tag)) {
        tags.push(tag);
      }
    }
  }

  return tags;
}

export function countTag(items: ItemView[], tag: string): number {
  let count = 0;

  for (const item of items) {
    if (item.tags.includes(tag)) {
      count++;
    }
  }

  return count;
}

// 单标签的渲染数据：标签名 + 条目数
export interface TagStat {
  tag: string;
  count: number;
}

// 标签 → 条目数（首次出现顺序）：一次遍历算完，供菜单一次性渲染。
// 语义与 `collectTags` + 每个 tag 各调一次 `countTag` 等价（同一 item 内的重复标签只计一次），
// 但只有一次数组遍历与一次 snapshot，标签多时不会 O(tag × item) 反复扫全量
export function collectTagStats(items: ItemView[]): TagStat[] {
  const order: string[] = [];
  const counts: Map<string, number> = new Map();

  for (const item of items) {
    const seen: Set<string> = new Set();

    for (const tag of item.tags) {
      if (tag.length === 0 || seen.has(tag)) {
        continue;
      }

      seen.add(tag);

      const current: number | undefined = counts.get(tag);

      if ('undefined' === typeof current) {
        order.push(tag);
        counts.set(tag, 1);
      } else {
        counts.set(tag, current + 1);
      }
    }
  }

  const stats: TagStat[] = [];

  for (const tag of order) {
    stats.push({ tag: tag, count: counts.get(tag) ?? 0 });
  }

  return stats;
}

export function countPinned(items: ItemView[]): number {
  let count = 0;

  for (const item of items) {
    if (item.pinned) {
      count++;
    }
  }

  return count;
}
