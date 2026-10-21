// 安全设置的端云同步：本地永远是权威（离线可用），服务端只作「换机 / 重装恢复」的副本。
//
// 策略：本地优先 + 脏标记
// - 任何本地变更（`setEnabled` 落盘成功）只置 `security.dirty = true`，模型不直接发请求；
// - `flush()`：dirty 时把**当前生效值整体**上行，成功后清 dirty（失败保留，下次登录 / 回前台再试）；
// - `reconcile()`：登录成功后调用。dirty → 先上行（以本地为准）；否则服务端有值 → 恢复到本地；
//   服务端无值 → 不动（老数据 / 首次使用，等用户下次变更自然上行）。
//
// 运行态（`AppLock.locked`、退后台临时遮挡）**永不参与同步**，服务端只保存用户意愿值。
import { Context } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../../App';
import { User as UserApi } from '../../api/User';
import { IMfaSecurity } from '../User';
import { KEY_SECURITY_DIRTY, Prefs, PrefsInstance } from '../../utils/Prefs';
import { AppLock } from './AppLock';
import { PrivacyWindow } from './PrivacyWindow';

const TAG: string = 'models/security';

export class SecuritySync {
  // 单飞：连续切换开关或多入口触发时，避免并发上行（后到的请求覆盖顺序不确定）
  private static _inFlight: boolean = false;

  // 登录后调和（只调一次，不要在每次页面显示时调用）
  static reconcile(context: Context, server: IMfaSecurity | null | undefined): void {
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

  // 把本地生效值推到服务端；非 dirty / 已有请求在飞时直接返回
  static flush(context: Context): void {
    if (SecuritySync._inFlight || !SecuritySync.isDirty(context)) {
      return;
    }

    const prefs: PrefsInstance | undefined = Prefs.open(context);

    if ('undefined' === typeof prefs) {
      return;
    }

    const privacyWindow: boolean = PrivacyWindow.instance().enabled;
    const appLock: boolean = AppLock.instance().enabled;
    const security: IMfaSecurity = { privacy_window: privacyWindow, app_lock: appLock };

    SecuritySync._inFlight = true;

    UserApi.editMfa(security)
      .then((): void => {
        SecuritySync._inFlight = false;
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

  private static isDirty(context: Context): boolean {
    return Prefs.getBoolean(Prefs.open(context), KEY_SECURITY_DIRTY, false);
  }
}
