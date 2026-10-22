// 安全设置的端云同步：本地永远是权威（离线可用），服务端只作「换机 / 重装恢复」的副本。
//
// 策略：本地优先 + 脏标记
// - 任何本地变更（`setEnabled` 落盘成功）只置 `security.dirty = true`，模型不直接发请求；
// - `flush()`：dirty 且有登录态时把**当前生效值整体**上行，成功后清 dirty（失败保留，下次登录 / 回前台再试）；
//   上行期间若又发生本地变更，成功后比对「已上行值 vs 当前值」，不一致就保留 dirty 并补发一次
//   （否则单飞窗口内那最后一次变更永远不会上行，本地与服务端长期不一致）；
// - `reconcile()`：登录成功后调用。dirty → 先上行（以本地为准）；否则服务端有值 → 恢复到本地；
//   服务端无值 → 不动（老数据 / 首次使用，等用户下次变更自然上行）；
// - `clearDirty()`：注销账号时调用。服务端副本随账号一起删除，此后不再有「未上行的本地变更」，
//   残留的 dirty 会让下一个登录的账号被上一个账号的本地值覆盖。
//
// 运行态（`AppLock.locked`、退后台临时遮挡）**永不参与同步**，服务端只保存用户意愿值。
import { Context } from '@kit.AbilityKit';
import { PersistenceV2 } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../../App';
import { User as UserApi } from '../../api/User';
import { Authorization } from '../Auth';
import { IMfaConfigSecurity } from '../User';
import { KEY_SECURITY_DIRTY, Prefs, PrefsInstance } from '../../utils/Prefs';
import { AppLock } from './AppLock';
import { PrivacyWindow } from './PrivacyWindow';

const TAG: string = 'models/security';

const authorization =
  (): Authorization => PersistenceV2.globalConnect({ type: Authorization, defaultCreator: () => new Authorization() })!;

// 未登录（首次使用 / 注销后 / refresh 失败）时不发请求：无意义，且 401 会经 http 拦截器把用户踢回登录页
const hasAccessToken = (): boolean => 'undefined' !== typeof authorization().accessToken;

export class SecuritySync {
  // 单飞：连续切换开关或多入口触发时，避免并发上行（后到的请求覆盖顺序不确定）
  private static _inFlight: boolean = false;

  // 登录后调和（只调一次，不要在每次页面显示时调用）
  static reconcile(context: Context, server: IMfaConfigSecurity | null | undefined): void {
    if (SecuritySync.isDirty(context)) {
      hilog.info(LogDomain.MODELS, TAG, 'reconcile: 本地有未同步变更，以本地为准上行');
      SecuritySync.flush(context);

      return;
    }

    if ('undefined' === typeof server || null === server) {
      hilog.info(LogDomain.MODELS, TAG, 'reconcile: 服务端无记录，保持本地设置');

      return;
    }

    if ('boolean' === typeof server.privacy_window) {
      PrivacyWindow.instance().applyRemote(context, server.privacy_window);
    }

    if ('boolean' === typeof server.app_lock) {
      AppLock.instance().applyRemote(context, server.app_lock);
    }
  }

  // 把本地生效值推到服务端；非 dirty / 未登录 / 已有请求在飞时直接返回
  static flush(context: Context): void {
    if (SecuritySync._inFlight || !SecuritySync.isDirty(context) || !hasAccessToken()) {
      return;
    }

    const prefs: PrefsInstance | undefined = Prefs.open(context);

    if ('undefined' === typeof prefs) {
      return;
    }

    const privacyWindow: boolean = PrivacyWindow.instance().enabled;
    const appLock: boolean = AppLock.instance().enabled;
    const security: IMfaConfigSecurity = { privacy_window: privacyWindow, app_lock: appLock };

    SecuritySync._inFlight = true;

    UserApi.editConfigMfa(security)
      .then((): void => {
        // 先复位单飞标记：下面的补发依赖它
        SecuritySync._inFlight = false;

        // 上行期间用户又改过开关：已上行的不是当前值，保留 dirty 并立即补发（dirty 未清，flush 会重新发）
        if (PrivacyWindow.instance().enabled !== privacyWindow || AppLock.instance().enabled !== appLock) {
          hilog.info(LogDomain.MODELS, TAG, 'sync_stale: 上行期间本地变更，保留脏标记后补发');

          SecuritySync.flush(context);

          return;
        }

        Prefs.putBoolean(prefs, KEY_SECURITY_DIRTY, false);
        hilog.info(LogDomain.MODELS, TAG, 'sync_done: privacyWindow=%{public}s, appLock=%{public}s',
          privacyWindow.toString(), appLock.toString());
      })
      .catch((e: Error): void => {
        // 本地设置已生效：失败只保留脏标记，下次登录 / 回前台重试，不打扰用户
        SecuritySync._inFlight = false;
        hilog.warn(LogDomain.MODELS, TAG, 'sync_failed: %{public}s', JSON.stringify(e));
      });
  }

  // 注销账号：清掉「待上行」语义，避免下一个登录的账号被上一个账号的本地值覆盖。
  // `security.privacyWindow` / `security.appLock` 本身是设备级偏好，保留；下一个账号登录时
  // 若服务端有值，由 reconcile → applyRemote 覆盖成本账号的设置
  static clearDirty(context: Context): void {
    const prefs: PrefsInstance | undefined = Prefs.open(context);

    if ('undefined' === typeof prefs) {
      return;
    }

    Prefs.putBoolean(prefs, KEY_SECURITY_DIRTY, false);
    hilog.info(LogDomain.MODELS, TAG, 'clear_dirty: 已清除安全设置的待上行标记');
  }

  private static isDirty(context: Context): boolean {
    return Prefs.getBoolean(Prefs.open(context), KEY_SECURITY_DIRTY, false);
  }
}
