// 卡片展示快照（preferences 持久化，库名 mfa_card）：主应用写账号数 / 首条 issuer+username /
// 时间戳，卡片提供方（FormExtensionAbility）同步读取并注入卡片。
// 快照只允许 id / issuer / username / count / updatedAt 五个字段，禁止写入 secret、验证码、access_token。
//
// 方法必须全部同步：FormExtensionAbility.onAddForm 是同步签名
// （SDK @ohos.app.form.FormExtensionAbility.d.ts:83），异步方法无法在其内 await。
//
// 跨进程可见性：主应用与卡片提供方是两个进程，preferences 实例按进程缓存在内存，
// 首次 getPreferences 后不再读持久化文件，因此看不到另一进程刚写入的值。典型故障：卡片添加后
// 主应用读不到 formId → 不推送 → 卡片数据停在添加那一刻。所有读写必须先走 prefs()。
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';

const PREFERENCES_NAME: string = 'mfa_card';
const KEY_SNAPSHOT: string = 'card_snapshot';
const KEY_FORM_IDS: string = 'card_form_ids';
// 卡片只展示首个账号，快照只留首条（多存即多暴露 issuer / username）
const SNAPSHOT_MAX_ITEMS: number = 1;

export interface SnapshotItem {
  id: string;

  issuer: string;

  username: string;
}

export interface SnapshotData {
  count: number;

  updatedAt: number;

  items: SnapshotItem[];
}

export class Snapshot {
  // 取本进程可用的 preferences 实例：先逐出本进程缓存，强制下次 get 从持久化文件重新加载，
  // 否则读不到另一进程刚写入的值（见文件头「跨进程可见性」）。同步接口会抛 BusinessError，
  // 这里兜住并返回 undefined，由调用方按「拿不到实例」处理。
  private static prefs(context: Context): preferences.Preferences | undefined {
    try {
      preferences.removePreferencesFromCacheSync(context, { name: PREFERENCES_NAME });

      return preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/form', '获取 preferences 实例失败: %{public}s', JSON.stringify(e));

      return undefined;
    }
  }

  // 解析 formId 列表原始值：JSON 可能损坏（非数组 / 非法 JSON），一律回落空列表
  private static parseFormIds(raw: string): string[] {
    if ('' === raw) {
      return [];
    }

    try {
      const parsed: Object = JSON.parse(raw) as Object;

      return Array.isArray(parsed) ? parsed as string[] : [];
    } catch (e) {
      hilog.warn(LogDomain.UTILS, 'utils/form', 'formId 列表解析失败，回落空列表: %{public}s',
        JSON.stringify(e));

      return [];
    }
  }

  // 纯函数装配：count = items.length，items 截断为前 SNAPSHOT_MAX_ITEMS 条
  private static build(items: SnapshotItem[], updatedAt: number): SnapshotData {
    return {
      count: items.length,
      updatedAt: updatedAt,
      items: items.slice(0, SNAPSHOT_MAX_ITEMS),
    };
  }

  static write(context: Context, items: SnapshotItem[]): void {
    try {
      const prefs: preferences.Preferences | undefined = Snapshot.prefs(context);

      if ('undefined' === typeof prefs) {
        return;
      }

      prefs.putSync(KEY_SNAPSHOT, JSON.stringify(Snapshot.build(items, Date.now())));
      prefs.flushSync();

      hilog.info(LogDomain.UTILS, 'utils/form', '快照写入: count=%{public}d', items.length);
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/form', '快照写入失败: %{public}s', JSON.stringify(e));
    }
  }

  static read(context: Context): SnapshotData {
    try {
      const prefs: preferences.Preferences | undefined = Snapshot.prefs(context);

      if ('undefined' === typeof prefs) {
        return { count: 0, updatedAt: 0, items: [] };
      }

      const raw: string = prefs.getSync(KEY_SNAPSHOT, '') as string;

      // 只打长度不打内容：rawLen=0 表示本进程读不到快照（跨进程缓存 / 从未写入）
      hilog.info(LogDomain.UTILS, 'utils/form', '快照读取: rawLen=%{public}d', raw.length);

      if ('' === raw) {
        return { count: 0, updatedAt: 0, items: [] };
      }

      const snapshot: SnapshotData = JSON.parse(raw) as SnapshotData;

      if (typeof snapshot.count !== 'number' || !Array.isArray(snapshot.items)) {
        return { count: 0, updatedAt: 0, items: [] };
      }

      return snapshot;
    } catch (e) {
      hilog.warn(LogDomain.UTILS, 'utils/form', '快照读取失败，回落空快照: %{public}s', JSON.stringify(e));

      return { count: 0, updatedAt: 0, items: [] };
    }
  }

  static addFormId(context: Context, formId: string): void {
    try {
      // 先读（内部已处理跨进程可见性），再取实例写，避免拿到被逐出缓存的旧实例
      const ids: string[] = Snapshot.listFormIds(context);

      if (ids.indexOf(formId) >= 0) {
        return;
      }

      const prefs: preferences.Preferences | undefined = Snapshot.prefs(context);

      if ('undefined' === typeof prefs) {
        return;
      }

      ids.push(formId);
      prefs.putSync(KEY_FORM_IDS, JSON.stringify(ids));
      prefs.flushSync();
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/form', 'formId 写入失败: %{public}s', JSON.stringify(e));
    }
  }

  static removeFormId(context: Context, formId: string): void {
    try {
      const ids: string[] = Snapshot.listFormIds(context);
      const index: number = ids.indexOf(formId);

      if (index < 0) {
        return;
      }

      const prefs: preferences.Preferences | undefined = Snapshot.prefs(context);

      if ('undefined' === typeof prefs) {
        return;
      }

      ids.splice(index, 1);
      prefs.putSync(KEY_FORM_IDS, JSON.stringify(ids));
      prefs.flushSync();
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/form', 'formId 删除失败: %{public}s', JSON.stringify(e));
    }
  }

  static listFormIds(context: Context): string[] {
    try {
      const prefs: preferences.Preferences | undefined = Snapshot.prefs(context);

      if ('undefined' === typeof prefs) {
        return [];
      }

      const raw: string = prefs.getSync(KEY_FORM_IDS, '') as string;

      return Snapshot.parseFormIds(raw);
    } catch (e) {
      hilog.warn(LogDomain.UTILS, 'utils/form', 'formId 列表读取失败，回落空列表: %{public}s',
        JSON.stringify(e));

      return [];
    }
  }
}
