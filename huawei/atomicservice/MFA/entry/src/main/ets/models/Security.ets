// 安全设置模型（防截屏开关 + 应用锁）的持久化层。
// 存储形态：preferences 库 `mfa_security` 单 key `security`，值为带 schema 版本的 JSON 字符串：
//   {"v":1,"screenProtect":true,"appLock":false}
// 为什么单 key + JSON：新增设置项不必再动 key，一次读取拿到一致快照；`v` 供未来版本升级/降级判定。
// 功能尚未正式发布，因此**不保留**历史双 key（screen_protect / app_lock）的迁移逻辑；旧 key 直接忽略（不读不删）。
// 读写契约：读异常/解析失败/版本不识别 → 默认值 + hilog（刻意 fail-open）；
// 写异常 → 回滚内存值并返回 false（不允许「显示已开、实际未开」）。
// 运行态锁定状态机见 models/AppLock.ets（绝不落盘）。
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { AppStorageV2 } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';

const PREFERENCES_NAME: string = 'mfa_security';
const KEY_SECURITY: string = 'security';
// 载荷 schema 版本：字段增删/语义变化时 +1，decode 内按版本分支处理
const SCHEMA_VERSION: number = 1;
const DEFAULT_SCREEN_PROTECT: boolean = true;
const DEFAULT_APP_LOCK: boolean = false;

// preferences 中的持久化载荷（JSON 序列化后写入单 key）
interface SecuritySettings {
  v: number;
  screenProtect: boolean;
  appLock: boolean;
}

@ObservedV2
export class Security {
  // 只读字段：设置项**只能**经 setScreenProtect / setAppLock 写入（两者失败时回滚内存值），
  // 开放 setter 等于给页面留一条绕开落盘校验的通道，会出现「显示已开、实际未开」
  @Trace
  private _screenProtect: boolean = DEFAULT_SCREEN_PROTECT;

  public get screenProtect(): boolean {
    return this._screenProtect;
  }

  @Trace
  private _appLock: boolean = DEFAULT_APP_LOCK;

  public get appLock(): boolean {
    return this._appLock;
  }

  static shared(): Security {
    return AppStorageV2.connect(Security, () => new Security())!;
  }

  // 取本进程可用的 preferences 实例。注意：本模块只在主进程读写，不要照抄 Form.ets 的
  // removePreferencesFromCacheSync（那是跨进程可见性处理，Form 主应用与卡片提供方是两个进程）
  private static prefs(context: Context): preferences.Preferences | undefined {
    try {
      return preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
    } catch (e) {
      hilog.error(LogDomain.MODELS, 'models/security', 'prefs_get_failed: %{public}s', JSON.stringify(e));

      return undefined;
    }
  }

  // 幂等，只由 EntryAbility 冷启动调用一次：一次 getSync 读出整份设置（key 不存在 → 空串 → 默认值，不写盘）。
  // 读异常用默认值 + hilog.error（刻意 fail-open，见技术设计 §3.5）
  load(context: Context): void {
    try {
      const prefs: preferences.Preferences | undefined = Security.prefs(context);

      if ('undefined' === typeof prefs) {
        return;
      }

      const settings: SecuritySettings = Security.decode(prefs.getSync(KEY_SECURITY, ''));

      this._screenProtect = settings.screenProtect;
      this._appLock = settings.appLock;
      hilog.info(LogDomain.MODELS, 'models/security', 'load: screenProtect=%{public}s, appLock=%{public}s, v=%{public}d',
        this._screenProtect.toString(), this._appLock.toString(), settings.v);
    } catch (e) {
      hilog.error(LogDomain.MODELS, 'models/security', 'load_failed: %{public}s', JSON.stringify(e));
    }
  }

  // 先改内存 → 整份设置落盘 → 成功 true；失败回滚内存 + hilog.error + 返回 false
  setScreenProtect(context: Context, on: boolean): boolean {
    const previous: boolean = this._screenProtect;

    return this.setField(context, 'screenProtect', on, previous, (value: boolean): void => {
      this._screenProtect = value;
    });
  }

  setAppLock(context: Context, on: boolean): boolean {
    const previous: boolean = this._appLock;

    return this.setField(context, 'appLock', on, previous, (value: boolean): void => {
      this._appLock = value;
    });
  }

  // 通用布尔设置项写入：内存值经 assign 闭包更新（@Trace 字段无法按字符串键动态赋值）→ 整份设置落盘 →
  // 失败回滚到 previous 并记日志，返回 false 由调用方提示用户
  private setField(context: Context, field: string, on: boolean, previous: boolean,
    assign: (value: boolean) => void): boolean {
    assign(on);

    const prefs: preferences.Preferences | undefined = Security.prefs(context);
    let error: string = 'prefs_unavailable';

    if ('undefined' !== typeof prefs) {
      const settings: SecuritySettings = {
        v: SCHEMA_VERSION,
        screenProtect: this._screenProtect,
        appLock: this._appLock,
      };

      try {
        prefs.putSync(KEY_SECURITY, JSON.stringify(settings));
        prefs.flushSync();

        return true;
      } catch (e) {
        error = JSON.stringify(e);
      }
    }

    assign(previous);
    hilog.error(LogDomain.MODELS, 'models/security', 'save_failed: field=%{public}s, err=%{public}s', field, error);

    return false;
  }

  // 解析持久化载荷：非字符串/空串/JSON 异常/版本不识别 → 整体回落默认值；
  // 版本匹配时逐字段校验，单个字段类型不符只回落该字段（保留可用字段）
  private static decode(raw: preferences.ValueType): SecuritySettings {
    const fallback: SecuritySettings = {
      v: SCHEMA_VERSION,
      screenProtect: DEFAULT_SCREEN_PROTECT,
      appLock: DEFAULT_APP_LOCK,
    };

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

      fallback.screenProtect =
        'boolean' === typeof parsed.screenProtect ? parsed.screenProtect : fallback.screenProtect;
      fallback.appLock = 'boolean' === typeof parsed.appLock ? parsed.appLock : fallback.appLock;

      return fallback;
    } catch (e) {
      hilog.error(LogDomain.MODELS, 'models/security', 'decode_failed: %{public}s', JSON.stringify(e));

      return fallback;
    }
  }
}
