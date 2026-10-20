// 安全设置（防截屏 / 应用锁）的**唯一持久化出口**，两个模型共用。
// 存储形态：单库 preferences `mfa` 下的**逐字段 key**（均在 utils/Prefs.ets 登记）：
//   security.privacyWindow = boolean
//   security.appLock       = boolean
// 为什么逐字段 key（而不是单 key + JSON 字符串 / object）：库走 GSKV（逐 key 实时落盘），
// 逐字段写入天然按字段隔离——不需要"读整份 → 合并 → 整份写"，也就没有"读失败不许写、否则会把另一个
// 字段静默重置为默认值"这个 fail-open 隐患（应用锁被悄悄关掉）。缺省即默认值，新增设置项 = 加一个 key，
// 不再需要 schema 版本号。
// 读写契约：读异常 / 类型不符 → 默认值 + hilog（刻意 fail-open）；写失败 → 返回 false 且**不修改任何内存态**
// （调用方据此提示用户，不允许「显示已开、实际未开」）。
// 一次 patch() 只允许携带一个字段（现网调用方各只改一项）；逐 key 写没有跨字段原子性。
// 运行态（PrivacyWindow 的遮挡、AppLock 的 locked）**绝不落盘**，不经过本文件。
import { Context } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../../App';
import { KEY_SECURITY_APP_LOCK, KEY_SECURITY_PRIVACY_WINDOW, Prefs, PrefsInstance } from '../../utils/Prefs';

const DEFAULT_PRIVACY_WINDOW: boolean = true;
const DEFAULT_APP_LOCK: boolean = false;
const TAG: string = 'models/security';

// 对外载荷（同时是将来同步到后端的 DTO）：字段名与 models/security 下的职责一一对应
export interface SecuritySettings {
  privacyWindow: boolean;
  appLock: boolean;
}

// 局部写入补丁：只带本次要改的字段（一次只允许带一个）
// （刻意不用 Partial<T>：可选字段显式声明更直观，也不依赖工具类型的支持范围）
export interface SecurityPatch {
  privacyWindow?: boolean;
  appLock?: boolean;
}

export class Store {
  static defaults(): SecuritySettings {
    const settings: SecuritySettings = {
      privacyWindow: DEFAULT_PRIVACY_WINDOW,
      appLock: DEFAULT_APP_LOCK,
    };

    return settings;
  }

  // 读整份设置：key 不存在 / 类型不符 / 读异常 → 默认值（不回写）
  static load(context: Context): SecuritySettings {
    const prefs: PrefsInstance | undefined = Prefs.open(context);

    if ('undefined' === typeof prefs) {
      return Store.defaults();
    }

    const settings: SecuritySettings = {
      privacyWindow: Prefs.getBoolean(prefs, KEY_SECURITY_PRIVACY_WINDOW, DEFAULT_PRIVACY_WINDOW),
      appLock: Prefs.getBoolean(prefs, KEY_SECURITY_APP_LOCK, DEFAULT_APP_LOCK),
    };

    hilog.info(LogDomain.MODELS, TAG, 'settings_load: privacyWindow=%{public}s, appLock=%{public}s',
      settings.privacyWindow.toString(), settings.appLock.toString());

    return settings;
  }

  // 只写本次要改的字段，不读、不合并、不影响另一个字段；任一字段写失败即返回 false
  static patch(context: Context, patch: SecurityPatch): boolean {
    const prefs: PrefsInstance | undefined = Prefs.open(context);

    if ('undefined' === typeof prefs) {
      hilog.error(LogDomain.MODELS, TAG, 'settings_save_failed: %{public}s', 'prefs_unavailable');

      return false;
    }

    let saved: boolean = true;

    if ('boolean' === typeof patch.privacyWindow) {
      saved = Prefs.putBoolean(prefs, KEY_SECURITY_PRIVACY_WINDOW, patch.privacyWindow) && saved;
    }

    if ('boolean' === typeof patch.appLock) {
      saved = Prefs.putBoolean(prefs, KEY_SECURITY_APP_LOCK, patch.appLock) && saved;
    }

    if (!saved) {
      hilog.error(LogDomain.MODELS, TAG, 'settings_save_failed: privacyWindow=%{public}s, appLock=%{public}s',
        String(patch.privacyWindow), String(patch.appLock));

      return false;
    }

    hilog.info(LogDomain.MODELS, TAG, 'settings_save: privacyWindow=%{public}s, appLock=%{public}s',
      String(patch.privacyWindow), String(patch.appLock));

    return true;
  }
}
