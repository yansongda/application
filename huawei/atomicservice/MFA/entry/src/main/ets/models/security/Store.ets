// 安全设置（防截屏 / 应用锁）的**唯一持久化出口**，两个模型共用。
// 存储形态：preferences 库 `security` 的单 key `settings`，值为带 schema 版本的 JSON：
//   {"v":1,"privacyWindow":true,"appLock":false}
// 为什么单 key + JSON：这份记录同时是**将来同步到后端的 DTO**——一次读取即一个完整可传输快照，
// 落到服务端不需要再写一层字段映射；`v` 供未来版本升级/降级判定。
// 读写契约：读异常/解析失败/版本不识别 → 默认值 + hilog（刻意 fail-open）；
// 写失败 → 返回 false 且**不修改任何内存态**（调用方据此提示用户，不允许「显示已开、实际未开」）。
// 运行态（PrivacyWindow 的遮挡、AppLock 的 locked）**绝不落盘**，不经过本文件。
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../../App';

const PREFERENCES_NAME: string = 'security';
const KEY_SETTINGS: string = 'settings';
// 载荷 schema 版本：字段增删/语义变化时 +1，decode 内按版本分支处理
const SCHEMA_VERSION: number = 1;
const DEFAULT_PRIVACY_WINDOW: boolean = true;
const DEFAULT_APP_LOCK: boolean = false;

// preferences 中的持久化载荷（JSON 序列化后写入单 key）；字段名与 models/security 下的职责一一对应
export interface SecuritySettings {
  v: number;
  privacyWindow: boolean;
  appLock: boolean;
}

// 局部写入补丁：只带本次要改的字段，其余字段由 patch 从磁盘读回后原样保留
// （刻意不用 Partial<T>：可选字段显式声明更直观，也不依赖工具类型的支持范围）
export interface SecurityPatch {
  privacyWindow?: boolean;
  appLock?: boolean;
}

export class Store {
  static defaults(): SecuritySettings {
    const settings: SecuritySettings = {
      v: SCHEMA_VERSION,
      privacyWindow: DEFAULT_PRIVACY_WINDOW,
      appLock: DEFAULT_APP_LOCK,
    };

    return settings;
  }

  // 读整份设置：key 不存在 → 默认值（不写盘）；读异常/解析失败/版本不识别 → 默认值 + hilog.error
  static load(context: Context): SecuritySettings {
    try {
      const prefs: preferences.Preferences | undefined = Store.prefs(context);

      if ('undefined' === typeof prefs) {
        return Store.defaults();
      }

      const settings: SecuritySettings = Store.decode(prefs.getSync(KEY_SETTINGS, ''));

      hilog.info(LogDomain.MODELS, 'models/security', 'settings_load: privacyWindow=%{public}s, appLock=%{public}s, v=%{public}d',
        settings.privacyWindow.toString(), settings.appLock.toString(), settings.v);

      return settings;
    } catch (e) {
      hilog.error(LogDomain.MODELS, 'models/security', 'settings_load_failed: %{public}s', JSON.stringify(e));

      return Store.defaults();
    }
  }

  // 读 → 合 → 整份写：调用方只传自己那一项，因此两个模型**不需要知道对方的当前值**（否则又互相依赖）。
  // 同进程单线程，读-合-写不存在竞态。
  static patch(context: Context, patch: SecurityPatch): boolean {
    const prefs: preferences.Preferences | undefined = Store.prefs(context);

    if ('undefined' === typeof prefs) {
      hilog.error(LogDomain.MODELS, 'models/security', 'settings_save_failed: %{public}s', 'prefs_unavailable');

      return false;
    }

    let settings: SecuritySettings = Store.defaults();

    try {
      settings = Store.decode(prefs.getSync(KEY_SETTINGS, ''));
    } catch (e) {
      // 读失败时**不写**：整份写入会把另一个字段静默重置为默认值（应用锁被悄悄关掉 = fail-open）
      hilog.error(LogDomain.MODELS, 'models/security', 'settings_save_skipped: read_failed, %{public}s',
        JSON.stringify(e));

      return false;
    }

    const next: SecuritySettings = {
      v: SCHEMA_VERSION,
      privacyWindow: 'boolean' === typeof patch.privacyWindow ? patch.privacyWindow : settings.privacyWindow,
      appLock: 'boolean' === typeof patch.appLock ? patch.appLock : settings.appLock,
    };

    try {
      prefs.putSync(KEY_SETTINGS, JSON.stringify(next));
      prefs.flushSync();

      hilog.info(LogDomain.MODELS, 'models/security', 'settings_save: privacyWindow=%{public}s, appLock=%{public}s',
        next.privacyWindow.toString(), next.appLock.toString());

      return true;
    } catch (e) {
      hilog.error(LogDomain.MODELS, 'models/security', 'settings_save_failed: %{public}s', JSON.stringify(e));

      return false;
    }
  }

  // 解析持久化载荷：非字符串/空串/JSON 异常/版本不识别 → 整体回落默认值；
  // 版本匹配时逐字段校验，单个字段类型不符只回落该字段（保留可用字段）
  private static decode(raw: preferences.ValueType): SecuritySettings {
    const fallback: SecuritySettings = Store.defaults();

    if ('string' !== typeof raw || 0 === raw.length) {
      return fallback;
    }

    try {
      const parsed: SecuritySettings = JSON.parse(raw) as SecuritySettings;

      // JSON 为 null / 非对象时字段访问会抛异常，由下方 catch 统一回落
      if ('number' !== typeof parsed.v || SCHEMA_VERSION !== parsed.v) {
        hilog.warn(LogDomain.MODELS, 'models/security', 'schema_unsupported: v=%{public}s',
          JSON.stringify(parsed.v));

        return fallback;
      }

      fallback.privacyWindow =
        'boolean' === typeof parsed.privacyWindow ? parsed.privacyWindow : fallback.privacyWindow;
      fallback.appLock = 'boolean' === typeof parsed.appLock ? parsed.appLock : fallback.appLock;

      return fallback;
    } catch (e) {
      hilog.error(LogDomain.MODELS, 'models/security', 'decode_failed: %{public}s', JSON.stringify(e));

      return fallback;
    }
  }

  // 取本进程可用的 preferences 实例。注意：安全设置只在主进程读写，**不要**照抄 Form.ets 的
  // removePreferencesFromCacheSync（那是跨进程可见性处理，主应用与卡片提供方是两个进程）
  private static prefs(context: Context): preferences.Preferences | undefined {
    try {
      return preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
    } catch (e) {
      hilog.error(LogDomain.MODELS, 'models/security', 'prefs_get_failed: %{public}s', JSON.stringify(e));

      return undefined;
    }
  }
}
