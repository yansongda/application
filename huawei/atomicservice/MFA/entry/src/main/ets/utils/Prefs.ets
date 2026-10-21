// preferences 的**唯一入口**：全应用只有一个库 `mfa`，所有读写都必须经本文件。
//
// 为什么是单库 + GSKV（而不是多个库 / 默认的 XML）：
// - 主应用与卡片提供方（FormExtensionAbility）是**两个进程**，两边都要读写同一份数据；
//   官方文档：XML 模式（默认）"无法保证进程并发安全，会有文件损坏和数据丢失的风险，不支持在多进程场景下使用"；
//   GSKV（API 18 起）"优点是支持多进程并发读写……针对多进程并发场景，推荐使用该存储模式"。
// - 存储语义差异（源码级）：XML 的 flush 会把**整个内存表**重写一遍（任一 key 变脏即整份落盘），
//   两个进程各自 flush 会互相覆盖未改动的 key（例如卡片进程把主应用刚写的应用锁开关回退 = fail-open）；
//   GSKV 的 put 是**逐 key 直接写 KV 库**，实时落盘、无整份覆盖。
// - 因此：GSKV 下单文件多进程读写安全；XML 只在 GSKV 不可用（预览器 / 跨平台构建）时作为**单进程**回落。
//
// 存储类型约束：同一库名一旦选定存储类型就**不可切换**（XML 文件与 GSKV 的 `.db` 文件互斥，
// 用错类型 getPreferencesSync 会抛 E_NOT_SUPPORTED），所以类型在进程内解析一次并缓存。
//
// 跨进程可见性：GSKV 下值小于 512KB 不入进程内缓存（源码 CACHED_THRESHOLDS），读到的是库里的最新值，
// 因此**不需要**驱逐缓存；XML 回落路径（单进程）仍沿用旧策略——`crossProcess: true` 时先
// removePreferencesFromCacheSync 再读，避免"首次 getPreferences 后不再读持久化文件"的老坑。
//
// flush：GSKV 实时落盘，不需要 flush；XML 必须 flushSync 才持久化，故只有 XML 下调用。
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';

// 单库名：不要再新增第二个 preferences 库
export const STORE_NAME: string = 'mfa';

// ── 单库 key 布局（唯一真相源；新增数据一律在此登记，避免跨域撞名）──
// 安全设置：逐字段 key（不存整份 JSON）——写入天然按字段隔离，不需要"读整份 → 合并 → 整份写"
export const KEY_SECURITY_PRIVACY_WINDOW: string = 'security.privacyWindow';
export const KEY_SECURITY_APP_LOCK: string = 'security.appLock';
// 安全设置「本地已变更、尚未上行服务端」的脏标记（boolean）；同步逻辑见 models/security/Sync.ets
export const KEY_SECURITY_DIRTY: string = 'security.dirty';
// 首页列表视图：筛选（kind 与 tag 语义耦合，合成一个 object key 保证原子写）与分组开关
export const KEY_INDEX_FILTER: string = 'index.filter';
export const KEY_INDEX_GROUPED: string = 'index.grouped';
// 卡片快照：主应用独写、卡片进程只读（object 值）
export const KEY_FORM_SNAPSHOT: string = 'form.snapshot';
// 卡片 formId：**每个 formId 一个 key**（`form.id.<formId>`），加/删卡是单 key 写/删，
// 不存在"两进程同时读改写同一个数组 key"的丢更新
export const KEY_FORM_ID_PREFIX: string = 'form.id.';

// 对外的实例类型别名：域代码只依赖 Prefs / PrefsInstance，不直接依赖 @kit.ArkData
export type PrefsInstance = preferences.Preferences;

export interface PrefsPolicy {
  // 是否用于跨进程场景：仅 XML 回落路径下生效（驱逐本进程缓存后再读），GSKV 下无作用
  crossProcess?: boolean;
}

const TAG: string = 'utils/prefs';
// getObject 的默认值（类型不符时 preferences 返回该默认值，随即被判定为"无对象"）
const EMPTY_OBJECT: Record<string, string> = {};

export class Prefs {
  // 进程内解析结果缓存：库名的存储类型创建后不可切换，解析一次即可
  private static _type: preferences.StorageType | undefined;

  // 取本进程可用的 preferences 实例；跨进程读取由 policy.crossProcess 表达（仅 XML 回落路径有实际动作）
  static open(context: Context, policy?: PrefsPolicy): PrefsInstance | undefined {
    const type: preferences.StorageType = Prefs.resolve(context);

    if (true === policy?.crossProcess && preferences.StorageType.XML === type) {
      Prefs.evict(context);
    }

    return Prefs.rawOpen(context, type, true);
  }

  static getString(p: PrefsInstance | undefined, key: string, defValue: string): string {
    if ('undefined' === typeof p) {
      return defValue;
    }

    try {
      const value: preferences.ValueType = p.getSync(key, defValue);

      return 'string' === typeof value ? value : defValue;
    } catch (e) {
      hilog.warn(LogDomain.UTILS, TAG, '读取失败，回落默认值: key=%{public}s, err=%{public}s', key,
        JSON.stringify(e));

      return defValue;
    }
  }

  static getBoolean(p: PrefsInstance | undefined, key: string, defValue: boolean): boolean {
    if ('undefined' === typeof p) {
      return defValue;
    }

    try {
      const value: preferences.ValueType = p.getSync(key, defValue);

      return 'boolean' === typeof value ? value : defValue;
    } catch (e) {
      hilog.warn(LogDomain.UTILS, TAG, '读取失败，回落默认值: key=%{public}s, err=%{public}s', key,
        JSON.stringify(e));

      return defValue;
    }
  }

  // 读 object 值：类型不符 / 读异常一律返回 undefined，由调用方按"没有数据"处理
  static getObject(p: PrefsInstance | undefined, key: string): object | undefined {
    if ('undefined' === typeof p) {
      return undefined;
    }

    try {
      const value: preferences.ValueType = p.getSync(key, EMPTY_OBJECT);

      return 'object' === typeof value ? value as object : undefined;
    } catch (e) {
      hilog.warn(LogDomain.UTILS, TAG, '读取失败，按无数据处理: key=%{public}s, err=%{public}s', key,
        JSON.stringify(e));

      return undefined;
    }
  }

  static putString(p: PrefsInstance | undefined, key: string, value: string): boolean {
    return Prefs.put(p, key, value);
  }

  static putBoolean(p: PrefsInstance | undefined, key: string, value: boolean): boolean {
    return Prefs.put(p, key, value);
  }

  static putObject(p: PrefsInstance | undefined, key: string, value: object): boolean {
    return Prefs.put(p, key, value);
  }

  static deleteKey(p: PrefsInstance | undefined, key: string): boolean {
    if ('undefined' === typeof p) {
      return false;
    }

    try {
      p.deleteSync(key);
      Prefs.flush(p);

      return true;
    } catch (e) {
      hilog.error(LogDomain.UTILS, TAG, '删除失败: key=%{public}s, err=%{public}s', key, JSON.stringify(e));

      return false;
    }
  }

  // 列出指定前缀的 key（GSKV 逐 key 存储后，枚举是唯一"批量读"手段；数据量级为个位数，成本可忽略）
  static keysWithPrefix(p: PrefsInstance | undefined, prefix: string): string[] {
    const keys: string[] = [];

    if ('undefined' === typeof p) {
      return keys;
    }

    try {
      const all: Record<string, preferences.ValueType> =
        p.getAllSync() as Record<string, preferences.ValueType>;

      Object.keys(all).forEach((key: string) => {
        if (key.startsWith(prefix)) {
          keys.push(key);
        }
      });

      return keys;
    } catch (e) {
      hilog.warn(LogDomain.UTILS, TAG, '枚举 key 失败，回落空列表: prefix=%{public}s, err=%{public}s', prefix,
        JSON.stringify(e));

      return [];
    }
  }

  // 便于日志排查：当前进程解析出的存储类型
  static label(): string {
    if ('undefined' === typeof Prefs._type) {
      return 'unresolved';
    }

    return preferences.StorageType.GSKV === Prefs._type ? 'gskv' : 'xml';
  }

  private static put(p: PrefsInstance | undefined, key: string, value: preferences.ValueType): boolean {
    if ('undefined' === typeof p) {
      return false;
    }

    try {
      p.putSync(key, value);
      Prefs.flush(p);

      return true;
    } catch (e) {
      hilog.error(LogDomain.UTILS, TAG, '写入失败: key=%{public}s, store=%{public}s, err=%{public}s', key,
        Prefs.label(), JSON.stringify(e));

      return false;
    }
  }

  // GSKV 实时落盘，flush 无必要；XML（含类型尚未解析的异常路径）必须 flushSync
  private static flush(p: PrefsInstance): void {
    if (preferences.StorageType.GSKV === Prefs._type) {
      return;
    }

    try {
      p.flushSync();
    } catch (e) {
      hilog.error(LogDomain.UTILS, TAG, '落盘失败: err=%{public}s', JSON.stringify(e));
    }
  }

  // 解析库的存储类型：优先 GSKV（平台支持且该库尚未以 XML 形态存在），否则回落 XML
  private static resolve(context: Context): preferences.StorageType {
    if ('undefined' !== typeof Prefs._type) {
      return Prefs._type;
    }

    if (Prefs.gskvSupported() && 'undefined' !== typeof Prefs.rawOpen(context, preferences.StorageType.GSKV, false)) {
      Prefs._type = preferences.StorageType.GSKV;
      hilog.info(LogDomain.UTILS, TAG, '存储类型: gskv, store=%{public}s', STORE_NAME);

      return Prefs._type;
    }

    // 回落 XML：仅预览器 / 跨平台构建（GSKV 不支持）或该库名已成 XML 形态（换类型需读旧写新，不支持原地切换）
    Prefs._type = preferences.StorageType.XML;
    hilog.warn(LogDomain.UTILS, TAG, '存储类型回落: xml（单进程，勿在多进程下写）, store=%{public}s', STORE_NAME);

    return Prefs._type;
  }

  private static gskvSupported(): boolean {
    try {
      return preferences.isStorageTypeSupported(preferences.StorageType.GSKV);
    } catch (e) {
      hilog.warn(LogDomain.UTILS, TAG, 'GSKV 能力探测失败，按不支持处理: err=%{public}s', JSON.stringify(e));

      return false;
    }
  }

  private static evict(context: Context): void {
    try {
      const options: preferences.Options = { name: STORE_NAME };

      preferences.removePreferencesFromCacheSync(context, options);
    } catch (e) {
      // 驱逐失败不影响后续 getPreferencesSync，最多读到本进程缓存的旧值
      hilog.warn(LogDomain.UTILS, TAG, '驱逐缓存失败: err=%{public}s', JSON.stringify(e));
    }
  }

  private static rawOpen(context: Context, type: preferences.StorageType,
    logAsError: boolean): PrefsInstance | undefined {
    try {
      const options: preferences.Options = { name: STORE_NAME, storageType: type };

      return preferences.getPreferencesSync(context, options);
    } catch (e) {
      if (logAsError) {
        hilog.error(LogDomain.UTILS, TAG, '打开失败: store=%{public}s, err=%{public}s', STORE_NAME,
          JSON.stringify(e));
      }

      return undefined;
    }
  }
}
