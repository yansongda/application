// 卡片展示快照（preferences 持久化，库名 mfa_card）：主应用写入账号数 / 前 2 条
// issuer+username / 时间戳，卡片提供方（FormExtensionAbility）同步读取并注入卡片。
// 快照只允许 id / issuer / username / count / updatedAt 五个字段，禁止写入
// secret、验证码、access_token。
//
// 全部方法必须为同步：FormExtensionAbility.onAddForm 是同步签名
// （SDK @ohos.app.form.FormExtensionAbility.d.ts:83），异步方法无法在其内 await。
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';

const PREFERENCES_NAME: string = 'mfa_card';
const KEY_SNAPSHOT: string = 'card_snapshot';
const KEY_FORM_IDS: string = 'card_form_ids';
const SNAPSHOT_MAX_ITEMS: number = 2;

export interface CardSnapshotItem {
  id: string;

  issuer: string;

  username: string;
}

export interface CardSnapshotData {
  count: number;

  updatedAt: number;

  items: CardSnapshotItem[];
}

// 纯函数：count = items.length，items 截断前 2 条。
export function buildSnapshot(items: CardSnapshotItem[], updatedAt: number): CardSnapshotData {
  return {
    count: items.length,
    updatedAt: updatedAt,
    items: items.slice(0, SNAPSHOT_MAX_ITEMS),
  };
}

export class CardSnapshot {
  static write(context: Context, items: CardSnapshotItem[]): void {
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      prefs.putSync(KEY_SNAPSHOT, JSON.stringify(buildSnapshot(items, Date.now())));
      prefs.flushSync();
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/card-snapshot', '快照写入失败: %{public}s', JSON.stringify(e));
    }
  }

  static read(context: Context): CardSnapshotData {
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      const raw: string = prefs.getSync(KEY_SNAPSHOT, '') as string;

      if ('' === raw) {
        return { count: 0, updatedAt: 0, items: [] };
      }

      const snapshot: CardSnapshotData = JSON.parse(raw) as CardSnapshotData;

      if (typeof snapshot.count !== 'number' || !Array.isArray(snapshot.items)) {
        return { count: 0, updatedAt: 0, items: [] };
      }

      return snapshot;
    } catch (e) {
      hilog.warn(LogDomain.UTILS, 'utils/card-snapshot', '快照读取失败，回落空快照: %{public}s', JSON.stringify(e));

      return { count: 0, updatedAt: 0, items: [] };
    }
  }

  static addFormId(context: Context, formId: string): void {
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      const ids: string[] = CardSnapshot.listFormIds(context);

      if (ids.indexOf(formId) >= 0) {
        return;
      }

      ids.push(formId);
      prefs.putSync(KEY_FORM_IDS, JSON.stringify(ids));
      prefs.flushSync();
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/card-snapshot', 'formId 写入失败: %{public}s', JSON.stringify(e));
    }
  }

  static removeFormId(context: Context, formId: string): void {
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      const ids: string[] = CardSnapshot.listFormIds(context);
      const index: number = ids.indexOf(formId);

      if (index < 0) {
        return;
      }

      ids.splice(index, 1);
      prefs.putSync(KEY_FORM_IDS, JSON.stringify(ids));
      prefs.flushSync();
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/card-snapshot', 'formId 删除失败: %{public}s', JSON.stringify(e));
    }
  }

  static listFormIds(context: Context): string[] {
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      const raw: string = prefs.getSync(KEY_FORM_IDS, '') as string;

      if ('' === raw) {
        return [];
      }

      const ids: string[] = JSON.parse(raw) as string[];

      if (!Array.isArray(ids)) {
        return [];
      }

      return ids;
    } catch (e) {
      hilog.warn(LogDomain.UTILS, 'utils/card-snapshot', 'formId 列表读取失败，回落空列表: %{public}s',
        JSON.stringify(e));

      return [];
    }
  }
}
