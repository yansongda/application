// 应用锁：① 用户设置 enabled（持久化，经 models/security/Store.ets）
// ② 运行态状态机（locked / 验证编排 / 防锁死降级）。
// 运行态**绝不落盘**——locked 一旦落盘，冷启动会读到上次的未锁定态，是安全 bug（技术设计 §3.1）；
// 因此只走 AppStorageV2.connect（进程内），进程结束即归零，locked 默认 false。
// 防截屏的窗口遮挡见 models/security/PrivacyWindow.ets；判定阈值见 utils/AppLockPolicy.ets。
import { Context } from '@kit.AbilityKit';
import { AppStorageV2 } from '@kit.ArkUI';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { userAuth } from '@kit.UserAuthenticationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LogDomain } from '../../App';
import { shouldRelock, shouldDebounceVerify } from '../../utils/AppLockPolicy';
import { SecurityPatch, Store } from './Store';

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

// challenge 生成结果：失败时带回原始错误码，由 verify 透传给 UI（禁止用非随机兜底）
interface ChallengeResult {
  challenge?: Uint8Array;
  code?: number;
}

@ObservedV2
export class AppLock {
  // 用户设置（持久化）：默认关。开启后「重新打开或离开 1 分钟后」需验证身份
  @Trace
  private _enabled: boolean = false;

  // 运行态（不持久化）：驱动 Home 的遮罩渲染与返回键消费
  @Trace
  private _locked: boolean = false;

  public get enabled(): boolean {
    return this._enabled;
  }

  public get locked(): boolean {
    return this._locked;
  }

  private _backgroundAt: number | undefined;
  private _verifying: boolean = false;
  private _generation: number = 0;
  private _lastFinishedAt: number | undefined; // 最近一次验证结束时间戳，供 shouldDebounceVerify 使用
  private _instance: userAuth.UserAuthInstance | undefined;

  static instance(): AppLock {
    return AppStorageV2.connect(AppLock, () => new AppLock())!;
  }

  // 冷启动读设置（由 EntryAbility.onCreate 调用一次，必须早于 onForeground）
  load(context: Context): void {
    this._enabled = Store.load(context).appLock;
    hilog.info(LogDomain.MODELS, 'models/security', 'app_lock_load: appLock=%{public}s', this._enabled.toString());
  }

  // 开关写入：**先落盘、成功才改内存**——失败返回 false 且内存不变（调用方提示用户）。
  // 防锁死降级（设备确无凭据）也走这里，落盘失败时内存仍为 true，仅日志留痕，不阻塞解锁
  setEnabled(context: Context, on: boolean): boolean {
    const patch: SecurityPatch = { appLock: on };

    if (!Store.patch(context, patch)) {
      hilog.error(LogDomain.MODELS, 'models/security', 'app_lock_save_failed: appLock=%{public}s', on.toString());

      return false;
    }

    this._enabled = on;
    hilog.info(LogDomain.MODELS, 'models/security', 'app_lock_set: appLock=%{public}s', on.toString());

    return true;
  }

  // 冷启动：locked = 持久化设置（AppLock 自身不落盘，由 enabled 决定初始值）。
  // 同时清空运行态残留：onWindowStageCreate 若被二次调用（stage 重建），残留的 _verifying = true 会让
  // verify() 直接 SKIPPED、onForeground 跳过重锁 —— 表现为「遮罩在但点解锁没反应」
  reset(): void {
    this._locked = this._enabled;
    this._backgroundAt = undefined;
    this._verifying = false;
    this._generation++;
    this._lastFinishedAt = undefined;
    this._instance = undefined;

    if (this._locked) {
      hilog.info(LogDomain.MODELS, 'models/security', 'lock: reason=%{public}s', 'cold_start');
    }
  }

  // 只加锁，绝不解锁。
  // _backgroundAt 无论是否重锁都清空：避免系统生命周期异常（未经过 onBackground 的连续 onForeground）
  // 用陈旧时间戳把正在使用的用户二次加锁。
  onForeground(now: number = Date.now()): void {
    const backgroundAt: number | undefined = this._backgroundAt;

    this._backgroundAt = undefined;

    if (!shouldRelock(this._enabled, backgroundAt, now) || this._verifying) {
      return;
    }

    this._locked = true;
    hilog.info(LogDomain.MODELS, 'models/security', 'lock: reason=%{public}s, elapsedMs=%{public}d',
      'timeout', now - backgroundAt!);
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
  //
  // 四段主线（行内注释 a–h 是细分步骤，按需跳转）：
  //   ① 闸门 : a 已在验证中 / b 3 秒防抖 → SKIPPED（不改 hint、**不**刷新防抖窗口）
  //   ② 探测 : c 三类型探测 + getEnrolledState 二次确认 → 降级 NO_CREDENTIAL / 上报 FAILED（**不**发起认证）
  //   ③ 发起 : d challenge / e 认证参数 / f 新建实例 + start
  //   ④ 结果 : g 结果码映射（含 NOT_ENROLLED 复探） / h 同步异常兜底
  // 状态不变式见 AGENTS.md「应用锁状态不变式」：任一出口漏复位 _verifying = 用户点解锁永远 SKIPPED = 锁死。
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
        this.degradeNoCredential(context);
        this.report(VerifyOutcome.NO_CREDENTIAL, onOutcome);
        return;
      }
      // 有凭据但当前不可用（如 PIN 过期）；pinCode 使 PIN_EXPIRED 定向文案可达
      this.report(VerifyOutcome.FAILED, onOutcome, probe.pinCode);
      return;
      // 禁止以空 authType 数组继续调用 getUserAuthInstance
    }

    // d. challenge：crypto framework 安全随机数（16 字节 ≤ 32B）；禁止用非随机兜底
    const challengeResult: ChallengeResult = AppLock.createChallenge();
    const challenge: Uint8Array | undefined = challengeResult.challenge;

    if ('undefined' === typeof challenge) {
      this.report(VerifyOutcome.FAILED, onOutcome, challengeResult.code);
      return;
    }

    // e. 验证参数（固定，非用户可配，见技术设计 §3.3 参数表）
    const authParam: userAuth.AuthParam = AppLock.buildAuthParam(available, challenge);
    // 不设置结果复用参数（reuseUnlockResult）——会让「设备已解锁但手机被他人拿走」失效
    const widgetParam: userAuth.WidgetParam = AppLock.buildWidgetParam(context);
    // 不设置导航按钮文本、不设置 2in1 弹窗上下文（见技术设计 §3.3 参数表）

    // f. 发起认证：每次验证新建实例（每个 UserAuthInstance 只能用于一次认证，官方原文）
    try {
      const instance: userAuth.UserAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam);

      this._verifying = true;
      const gen: number = ++this._generation;

      instance.on('result', {
        onResult: (result: userAuth.UserAuthResult): void => {
          // g. 每次实例只消费一次结果：先摘监听，再按世代号丢弃退后台后到达的旧结果（onBackground 已 cancel + generation++）
          instance.off('result');

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
                this.degradeNoCredential(context);
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

          // 只清理本次实例：退后台重入时 _instance 可能已指向新实例
          if (this._instance === instance) {
            this._instance = undefined;
          }

          this.report(outcome, onOutcome, result.result); // 透传原始错误码
        },
      });
      this._instance = instance;
      instance.start();
    } catch (e) {
      // h. 同步异常统一兜底（getUserAuthInstance / on / start）
      this._verifying = false;
      this._lastFinishedAt = Date.now(); // 同步失败同样计入防抖窗口，避免连续拉起系统认证控件
      this._instance = undefined;
      this._generation++; // 作废可能已注册到失败实例上的回调（start 抛错但认证已拉起时也不会串场）
      hilog.error(LogDomain.MODELS, 'models/security', 'verify_failed: %{public}s', JSON.stringify(e));
      this.report(VerifyOutcome.FAILED, onOutcome, (e as BusinessError).code);
    }
  }

  // 安全随机 challenge（官方要求安全随机数；16 字节，>32 字节会报 12500008）。
  // 异常时返回原始 code 供 UI 映射，不抛、不兜底伪随机数。
  private static createChallenge(): ChallengeResult {
    try {
      const challenge: Uint8Array | undefined = cryptoFramework.createRandom().generateRandomSync(16)?.data;

      return { challenge: challenge };
    } catch (e) {
      hilog.error(LogDomain.MODELS, 'models/security', 'challenge_failed: %{public}s', JSON.stringify(e));

      return { challenge: undefined, code: (e as BusinessError).code };
    }
  }

  // 固定验证参数（非用户可配，见技术设计 §3.3 参数表）：
  // ATL3 匹配应用锁风险；skipLockedBiometricAuth 让生物识别锁定后直接切 PIN；
  // 不设置 reuseUnlockResult（否则「设备已解锁但手机被他人拿走」失效）
  private static buildAuthParam(available: userAuth.UserAuthType[],
    challenge: Uint8Array): userAuth.AuthParam {
    const authParam: userAuth.AuthParam = {
      challenge: challenge,
      authType: available,
      authTrustLevel: userAuth.AuthTrustLevel.ATL3,
      skipLockedBiometricAuth: true,
    };

    return authParam;
  }

  // 防锁死降级：设备确无凭据时自动解锁 + 自动关闭应用锁（技术设计 §3.5 唯一可接受的降级路径）。
  // setEnabled 已保证「落盘失败不改内存」，这里仅记日志（下次冷启动会重演降级，但不会锁死用户）
  private degradeNoCredential(context: Context): void {
    if (!this.setEnabled(context, false)) {
      hilog.error(LogDomain.MODELS, 'models/security', 'disable_persist_failed: %{public}s', 'no_credential');
    }

    this.unlock();
    hilog.warn(LogDomain.MODELS, 'models/security', 'disable: reason=%{public}s', 'no_credential');
  }

  // 认证控件标题：SDK 要求 string（不接受 Resource），且本机 SDK 无 resourceToString 全局函数
  private static buildWidgetParam(context: Context): userAuth.WidgetParam {
    let title: string = '';

    try {
      title = context.resourceManager.getStringSync($r('app.string.lock_page_verify_title').id);
    } catch (e) {
      // 文案读取失败属资源异常路径：记 error 后用空标题继续发起认证（防锁死优先，R2：不得让用户失去解锁路径）
      hilog.error(LogDomain.MODELS, 'models/security', 'title_get_failed: %{public}s', JSON.stringify(e));
    }

    return { title: title };
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
    hilog.info(LogDomain.MODELS, 'models/security', 'verify_result: outcome=%{public}s, code=%{public}d',
      outcome.toString(), 'undefined' === typeof code ? -1 : code);
    if ('function' === typeof onOutcome) {
      onOutcome(outcome, code);
    }
  }
}
