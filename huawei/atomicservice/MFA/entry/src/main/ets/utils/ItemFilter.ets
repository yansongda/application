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

export function countPinned(items: ItemView[]): number {
  let count = 0;

  for (const item of items) {
    if (item.pinned) {
      count++;
    }
  }

  return count;
}
