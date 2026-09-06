import { STORAGE } from "@constant/app";
import { PATH } from "@constant/totp";
import http from "@utils/http";
import logger from "@utils/logger";
import type { CacheItem, Item, TotpCache } from "types/totp";

const readCache = (): TotpCache | null => {
  try {
    const raw = wx.getStorageSync(STORAGE.TOTP_CACHE);

    if (!raw) {
      return null;
    }

    const cache = raw as TotpCache;

    if (!Array.isArray(cache.items)) {
      logger.warning("TOTP 本地缓存结构异常，已忽略");

      return null;
    }

    return cache;
  } catch (e: unknown) {
    logger.warning("读取 TOTP 本地缓存失败", e);

    return null;
  }
};

const writeCache = (cache: TotpCache): void => {
  wx.setStorageSync(STORAGE.TOTP_CACHE, cache);
};

const upsertItem = (item: CacheItem): void => {
  // 缓存不存在时以空缓存为底座承接新条目。
  const cache: TotpCache = readCache() ?? { items: [] };

  const index = cache.items.findIndex((i) => i.id === item.id);

  if (index === -1) {
    cache.items.push(item);
  } else {
    cache.items[index] = item;
  }

  writeCache(cache);
};

const removeItem = (id: string): void => {
  const cache = readCache();

  if (!cache) {
    return;
  }

  cache.items = cache.items.filter((i) => i.id !== id);

  writeCache(cache);
};

const updateItemFields = (
  id: string,
  fields: Partial<Pick<CacheItem, "issuer" | "username">>,
): void => {
  const cache = readCache();

  if (!cache) {
    return;
  }

  const index = cache.items.findIndex((i) => i.id === id);

  if (index === -1) {
    return;
  }

  cache.items[index] = { ...cache.items[index], ...fields };

  writeCache(cache);
};

const applySort = (orderedIds: string[]): void => {
  const cache = readCache();

  if (!cache) {
    return;
  }

  const itemById = new Map(cache.items.map((i) => [i.id, i]));
  const ordered: CacheItem[] = [];
  const consumed = new Set<string>();

  for (const id of orderedIds) {
    const item = itemById.get(id);

    if (typeof item !== "undefined") {
      ordered.push(item);
      consumed.add(id);
    }
  }

  // 未命中的 id 保持在末尾原序。
  for (const item of cache.items) {
    if (!consumed.has(item.id)) {
      ordered.push(item);
    }
  }

  cache.items = ordered;

  writeCache(cache);
};

const syncFromRemote = async (): Promise<TotpCache> => {
  // /all 响应已携带 config.secret（PR #162 review 方案 A），单接口完成同步。
  const items = await http.post<Item[]>(PATH.ALL, {});

  const cacheItems: CacheItem[] = items.map((item) => ({
    id: item.id,
    issuer: item.issuer,
    username: item.username,
    secret: item.config.secret,
    period: item.config.period,
  }));

  const cache: TotpCache = {
    items: cacheItems,
  };

  writeCache(cache);

  return cache;
};

export {
  applySort,
  readCache,
  removeItem,
  syncFromRemote,
  updateItemFields,
  upsertItem,
  writeCache,
};
