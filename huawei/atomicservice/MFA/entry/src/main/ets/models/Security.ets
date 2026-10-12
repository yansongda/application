// 安全设置模型（防截屏开关 + 应用锁）与运行态锁定状态机。
// 设置走 preferences（同步写、异常可观测）；运行态**绝不落盘**——locked 一旦落盘，
// 冷启动会读到上次的未锁定态，是安全 bug（技术设计 §3.1）。
// 运行态由 AppStorageV2.connect 保存在进程内，进程结束即归零，locked 默认 false。
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { AppStorageV2 } from '@kit.ArkUI';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { userAuth } from '@kit.UserAuthenticationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LogDomain } from '../App';
import { LOCK_TIMEOUT_MS, VERIFY_DEBOUNCE_MS, shouldRelock, shouldDebounceVerify } from '../utils/LockPolicy';

const PREFERENCES_NAME: string = 'mfa_security';
const KEY_SCREEN_PROTECT: string = 'screen_protect';
const KEY_APP_LOCK: string = 'app_lock';

export enum VerifyOutcome {
  SUCCESS,
  CANCELED,
  FAILED,
  SKIPPED,
  NO_CREDENTIAL,
}

// 能力探测结果：available = 探测可用的认证类型（保持 PIN → FACE → FINGERPRINT 优先级）；
// pinCode = PIN 的原始错误码（如 12500013 PIN_EXPIRED），供 UI 映射定向文案
interface ProbeResult {
  available: userAuth.UserAuthType[];
  pinCode?: number;
}

@ObservedV2
export class Security {
  @Trace
  private _screenProtect: boolean = true;

  public get screenProtect(): boolean {
    return this._screenProtect;
  }

  public set screenProtect(value: boolean) {
    this._screenProtect = value;
  }

  @Trace
  private _appLock: boolean = false;

  public get appLock(): boolean {
    return this._appLock;
  }

  public set appLock(value: boolean) {
    this._appLock = value;
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

  // 幂等，只由 EntryAbility 冷启动调用一次；读两个 key（默认 true / false）。
  // 读异常用默认值 + hilog.error（刻意 fail-open，见技术设计 §3.5）
  load(context: Context): void {
    try {
      const prefs: preferences.Preferences | undefined = Security.prefs(context);

      if ('undefined' === typeof prefs) {
        return;
      }

      this._screenProtect = prefs.getSync(KEY_SCREEN_PROTECT, true) as boolean;
      this._appLock = prefs.getSync(KEY_APP_LOCK, false) as boolean;
      hilog.info(LogDomain.MODELS, 'models/security', 'load: screenProtect=%{public}s, appLock=%{public}s',
        this._screenProtect.toString(), this._appLock.toString());
    } catch (e) {
      hilog.error(LogDomain.MODELS, 'models/security', 'load_failed: %{public}s', JSON.stringify(e));
    }
  }

  // 先写内存 → 落盘 → 成功 true；失败回滚内存 + hilog.error + 返回 false
  // （不允许"显示已开、实际未开"，回滚后 UI 开关弹回原位）
  setScreenProtect(context: Context, on: boolean): boolean {
    const previous: boolean = this._screenProtect;

    this._screenProtect = on;
    if (Security.write(context, KEY_SCREEN_PROTECT, on)) {
      return true;
    }
    this._screenProtect = previous;
    hilog.error(LogDomain.MODELS, 'models/security', 'set_failed: key=%{public}s', KEY_SCREEN_PROTECT);

    return false;
  }

  setAppLock(context: Context, on: boolean): boolean {
    const previous: boolean = this._appLock;

    this._appLock = on;
    if (Security.write(context, KEY_APP_LOCK, on)) {
      return true;
    }
    this._appLock = previous;
    hilog.error(LogDomain.MODELS, 'models/security', 'set_failed: key=%{public}s', KEY_APP_LOCK);

    return false;
  }

  private static write(context: Context, key: string, value: boolean): boolean {
    try {
      const prefs: preferences.Preferences | undefined = Security.prefs(context);

      if ('undefined' === typeof prefs) {
        return false;
      }

      prefs.putSync(key, value);
      prefs.flushSync();

      return true;
    } catch (e) {
      hilog.error(LogDomain.MODELS, 'models/security', 'write_failed: key=%{public}s, err=%{public}s',
        key, JSON.stringify(e));

      return false;
    }
  }
}

@ObservedV2
export class AppLock {
  @Trace
  private _locked: boolean = false;

  public get locked(): boolean {
    return this._locked;
  }

  private _backgroundAt: number | undefined;
  private _verifying: boolean = false;
  private _generation: number = 0;
  private _lastFinishedAt: number | undefined; // 最近一次验证结束时间戳，供 shouldDebounceVerify 使用
  private _instance: userAuth.UserAuthInstance | undefined;

  static shared(): AppLock {
    return AppStorageV2.connect(AppLock, () => new AppLock())!;
  }

  // 冷启动：locked = 持久化设置（AppLock 自身不落盘，由 Security.appLock 决定初始值）
  reset(appLock: boolean): void {
    this._locked = appLock;
    if (appLock) {
      hilog.info(LogDomain.MODELS, 'models/security', 'lock: reason=%{public}s', 'cold_start');
    }
  }

  // 只加锁，绝不解锁
  onForeground(now: number = Date.now()): void {
    const backgroundAt: number | undefined = this._backgroundAt;

    if (shouldRelock(Security.shared().appLock, backgroundAt, now) && !this._verifying) {
      this._locked = true;
      hilog.info(LogDomain.MODELS, 'models/security', 'lock: reason=%{public}s, elapsedMs=%{public}d',
        'timeout', now - backgroundAt!);
      this._backgroundAt = undefined;
    }
  }

  onBackground(): void {
    this._backgroundAt = Date.now();
    try {
      this._instance?.cancel();
    } catch (e) {
      hilog.warn(LogDomain.MODELS, 'models/security', 'cancel_failed: %{public}s', JSON.stringify(e));
    }
    this._verifying = false;
    this._generation++;
    this._instance = undefined;
  }

  unlock(): void {
    this._locked = false;
  }

  // 发起身份认证。code = 原始 userAuth.UserAuthResultCode，供 UI 映射定向文案（LOCKED / PIN_EXPIRED）
  verify(context: Context, onOutcome?: (outcome: VerifyOutcome, code?: number) => void): void {
    // a. 已在验证中（并发保护，官方"避免同时发起多个认证请求"）
    if (this._verifying) {
      this.report(VerifyOutcome.SKIPPED, onOutcome);
      return;
    }

    // b. 3 秒防抖（验证结束后短时间内重复触发直接跳过，避免系统认证控件闪烁）
    if (shouldDebounceVerify(this._lastFinishedAt, Date.now())) {
      hilog.info(LogDomain.MODELS, 'models/security', 'verify_skip: reason=%{public}s', 'debounce');
      this.report(VerifyOutcome.SKIPPED, onOutcome);
      return;
    }

    // c. 能力探测：全部不可用 → 二次确认"设备是否真的没有任何凭据"（防锁死降级，技术设计 §3.3）
    const probe: ProbeResult = this.probe();
    const available: userAuth.UserAuthType[] = probe.available;

    if (0 === available.length) {
      let confirmed: boolean = false;

      try {
        const enrolled: userAuth.EnrolledState = userAuth.getEnrolledState(userAuth.UserAuthType.PIN);

        confirmed = (0 === enrolled.credentialCount);
      } catch (e) {
        // getEnrolledState 在未录入时自抛 12500010：未录入即无凭据；其余异常视为未确认
        confirmed = (12500010 === (e as BusinessError).code);
      }

      if (confirmed) {
        // 设备确无凭据：自动解锁 + 自动关闭应用锁（唯一可接受的防锁死路径，见技术设计 §3.5）
        if (!Security.shared().setAppLock(context, false)) {
          // 落盘失败时内存已回滚为 true，仅记日志（下次冷启动会重演降级，但不会锁死用户）
          hilog.error(LogDomain.MODELS, 'models/security', 'disable_persist_failed: %{public}s', 'no_credential');
        }
        this.unlock();
        hilog.error(LogDomain.MODELS, 'models/security', 'disable: reason=%{public}s', 'no_credential');
        this.report(VerifyOutcome.NO_CREDENTIAL, onOutcome);
        return;
      }
      // 有凭据但当前不可用（如 PIN 过期）；pinCode 使 PIN_EXPIRED 定向文案可达
      this.report(VerifyOutcome.FAILED, onOutcome, probe.pinCode);
      return;
      // 禁止以空 authType 数组继续调用 getUserAuthInstance
    }

    // d. challenge：crypto framework 安全随机数（16 字节 ≤ 32B）；禁止用非随机兜底
    let challenge: Uint8Array | undefined;

    try {
      challenge = cryptoFramework.createRandom().generateRandomSync(16)?.data;
    } catch (e) {
      this.report(VerifyOutcome.FAILED, onOutcome, (e as BusinessError).code);
      return;
    }
    if ('undefined' === typeof challenge) {
      this.report(VerifyOutcome.FAILED, onOutcome);
      return;
    }

    // e. 验证参数（固定，非用户可配，见技术设计 §3.3 参数表）
    const authParam: userAuth.AuthParam = {
      challenge: challenge,
      authType: available,
      authTrustLevel: userAuth.AuthTrustLevel.ATL3,
      skipLockedBiometricAuth: true,
    };
    // 不设置结果复用参数（reuseUnlockResult）——会让「设备已解锁但手机被他人拿走」失效
    const widgetParam: userAuth.WidgetParam = {
      // 该参数类型为 string（不接受 Resource）；本机 SDK 无 resourceToString 全局函数
      title: context.resourceManager.getStringSync($r('app.string.lock_page_verify_title').id),
    };
    // 不设置导航按钮文本、不设置 2in1 弹窗上下文（见技术设计 §3.3 参数表）

    // f. 发起认证：每次验证新建实例（每个 UserAuthInstance 只能用于一次认证，官方原文）
    try {
      const instance: userAuth.UserAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam);

      this._verifying = true;
      const gen: number = ++this._generation;

      instance.on('result', {
        onResult: (result: userAuth.UserAuthResult): void => {
          // g. 退后台后到达的旧结果丢弃（onBackground 已 cancel + generation++）
          if (gen !== this._generation) {
            return;
          }

          let outcome: VerifyOutcome = VerifyOutcome.FAILED;

          switch (result.result) {
            case userAuth.UserAuthResultCode.SUCCESS:
              outcome = VerifyOutcome.SUCCESS;
              this.unlock();
              break;
            case userAuth.UserAuthResultCode.CANCELED:
            case userAuth.UserAuthResultCode.TIMEOUT:
            case userAuth.UserAuthResultCode.CANCELED_FROM_WIDGET:
              outcome = VerifyOutcome.CANCELED;
              break;
            case userAuth.UserAuthResultCode.NOT_ENROLLED: {
              // 重新探测：为空 → 同 (c) 防锁死降级路径；非空 → 普通失败（避免误关闭应用锁）
              const reprobe: ProbeResult = this.probe();

              if (0 === reprobe.available.length) {
                if (!Security.shared().setAppLock(context, false)) {
                  hilog.error(LogDomain.MODELS, 'models/security', 'disable_persist_failed: %{public}s',
                    'no_credential');
                }
                this.unlock();
                hilog.error(LogDomain.MODELS, 'models/security', 'disable: reason=%{public}s', 'no_credential');
                outcome = VerifyOutcome.NO_CREDENTIAL;
              }
              break;
            }
            case userAuth.UserAuthResultCode.FAIL:
            case userAuth.UserAuthResultCode.LOCKED:
            case userAuth.UserAuthResultCode.PIN_EXPIRED:
            case userAuth.UserAuthResultCode.GENERAL_ERROR:
            case userAuth.UserAuthResultCode.BUSY:
            case userAuth.UserAuthResultCode.INVALID_PARAMETERS:
            default:
              // 枚举外的未知码按常量穷举兜底为 FAILED（前向兼容）
              outcome = VerifyOutcome.FAILED;
              break;
          }

          this._verifying = false;
          this._lastFinishedAt = Date.now();
          this._instance?.off('result');
          this._instance = undefined;
          this.report(outcome, onOutcome, result.result); // 透传原始错误码
        },
      });
      this._instance = instance;
      instance.start();
    } catch (e) {
      // h. 同步异常统一兜底（getUserAuthInstance / on / start）
      this._verifying = false;
      this._instance = undefined;
      hilog.error(LogDomain.MODELS, 'models/security', 'verify_failed: %{public}s', JSON.stringify(e));
      this.report(VerifyOutcome.FAILED, onOutcome, (e as BusinessError).code);
    }
  }

  // 依次探测 PIN / FACE / FINGERPRINT（ATL3）：不抛错即认为可用；
  // 抛错则记 warn 并保留 PIN 的错误码（pinCode）——PIN_EXPIRED 在探测阶段即抛出，
  // 若丢弃该码，设计 §3.5 承诺的定向文案在主路径上永远不可达
  private probe(): ProbeResult {
    const available: userAuth.UserAuthType[] = [];
    let pinCode: number | undefined;
    const types: userAuth.UserAuthType[] = [
      userAuth.UserAuthType.PIN,
      userAuth.UserAuthType.FACE,
      userAuth.UserAuthType.FINGERPRINT,
    ];

    for (const t of types) {
      try {
        userAuth.getAvailableStatus(t, userAuth.AuthTrustLevel.ATL3);
        available.push(t);
      } catch (e) {
        const code: number = (e as BusinessError).code;

        hilog.warn(LogDomain.MODELS, 'models/security', 'probe_unavailable: type=%{public}d, code=%{public}d',
          t, code);
        if (userAuth.UserAuthType.PIN === t && 'undefined' === typeof pinCode) {
          pinCode = code;
        }
      }
    }

    return { available: available, pinCode: pinCode };
  }

  private report(outcome: VerifyOutcome, onOutcome?: (o: VerifyOutcome, code?: number) => void,
    code?: number): void {
    hilog.info(LogDomain.MODELS, 'models/security', 'unlock: outcome=%{public}s, code=%{public}d',
      outcome.toString(), 'undefined' === typeof code ? -1 : code);
    if ('function' === typeof onOutcome) {
      onOutcome(outcome, code);
    }
  }
}
