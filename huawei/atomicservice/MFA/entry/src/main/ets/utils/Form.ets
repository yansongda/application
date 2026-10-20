// 卡片展示快照（单库 preferences `mfa` 的 `form.snapshot` / `form.id.<formId>`）：主应用只写账号数与
// 时间戳，卡片提供方（FormExtensionAbility）同步读取并注入卡片。
// 快照只存 count / updatedAt，不落任何账号明细（issuer / username 等一律不入盘）。
//
// 方法必须全部同步：FormExtensionAbility.onAddForm 是同步签名
// （SDK @ohos.app.form.FormExtensionAbility.d.ts:83），异步方法无法在其内 await。
//
// 跨进程：主应用与卡片提供方是两个进程，读写统一经 utils/Prefs.ets（库 `mfa` 走 GSKV，官方支持多进程并发
// 读写、逐 key 实时落盘）。formId 采用**逐 key**（`form.id.<formId>`）而不是一个数组 key：加卡 / 删卡
// 都是单 key 写 / 删，避免"两个进程同时读改写同一数组"的丢更新。
import { Context } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';
import { KEY_FORM_ID_PREFIX, KEY_FORM_SNAPSHOT, Prefs, PrefsInstance, PrefsPolicy } from './Prefs';

// 卡片相关读写全程跨进程（主应用 ↔ 卡片提供方）
const CROSS_PROCESS: PrefsPolicy = { crossProcess: true };
// formId key 的存在性标记：value 不承载信息，只表示"该卡片仍存在"
const FORM_ID_MARK: string = '1';
const TAG: string = 'utils/form';

export interface SnapshotData {
  count: number;

  updatedAt: number;
}

export class Snapshot {
  static write(context: Context, count: number): void {
    const prefs: PrefsInstance | undefined = Prefs.open(context, CROSS_PROCESS);

    if ('undefined' === typeof prefs) {
      return;
    }

    const snapshot: SnapshotData = { count: count, updatedAt: Date.now() };

    if (!Prefs.putObject(prefs, KEY_FORM_SNAPSHOT, snapshot)) {
      hilog.error(LogDomain.UTILS, TAG, '快照写入失败: count=%{public}d', count);

      return;
    }

    hilog.info(LogDomain.UTILS, TAG, '快照写入: count=%{public}d', count);
  }

  static read(context: Context): SnapshotData {
    const empty: SnapshotData = { count: 0, updatedAt: 0 };
    const prefs: PrefsInstance | undefined = Prefs.open(context, CROSS_PROCESS);

    if ('undefined' === typeof prefs) {
      return empty;
    }

    const raw: object | undefined = Prefs.getObject(prefs, KEY_FORM_SNAPSHOT);

    // 读不到快照（跨进程未同步 / 从未写入）时按空态处理
    if ('undefined' === typeof raw) {
      hilog.info(LogDomain.UTILS, TAG, '快照缺失，按空态处理');

      return empty;
    }

    const snapshot: SnapshotData = raw as SnapshotData;

    if ('number' !== typeof snapshot.count) {
      return empty;
    }

    return { count: snapshot.count, updatedAt: 'number' === typeof snapshot.updatedAt ? snapshot.updatedAt : 0 };
  }

  static addFormId(context: Context, formId: string): void {
    const prefs: PrefsInstance | undefined = Prefs.open(context, CROSS_PROCESS);

    if ('undefined' === typeof prefs) {
      return;
    }

    // 同 key 覆盖写，天然幂等（重复 onAddForm 不会产生重复项）
    if (!Prefs.putString(prefs, KEY_FORM_ID_PREFIX + formId, FORM_ID_MARK)) {
      hilog.error(LogDomain.UTILS, TAG, 'formId 写入失败: formId=%{public}s', formId);
    }
  }

  static removeFormId(context: Context, formId: string): void {
    const prefs: PrefsInstance | undefined = Prefs.open(context, CROSS_PROCESS);

    if ('undefined' === typeof prefs) {
      return;
    }

    if (!Prefs.deleteKey(prefs, KEY_FORM_ID_PREFIX + formId)) {
      hilog.error(LogDomain.UTILS, TAG, 'formId 删除失败: formId=%{public}s', formId);
    }
  }

  static listFormIds(context: Context): string[] {
    const prefs: PrefsInstance | undefined = Prefs.open(context, CROSS_PROCESS);

    if ('undefined' === typeof prefs) {
      return [];
    }

    const ids: string[] = [];

    Prefs.keysWithPrefix(prefs, KEY_FORM_ID_PREFIX).forEach((key: string) => {
      ids.push(key.substring(KEY_FORM_ID_PREFIX.length));
    });

    return ids;
  }
}
