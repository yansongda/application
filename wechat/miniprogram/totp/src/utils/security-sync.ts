import userApi from "../api/user";
import type { MfaConfigSecurity } from "../types/user";
import { getTokenBundle } from "./app";
import { applyRemote as applyAppLockRemote } from "./app-lock";
import logger from "./logger";
import { applyRemote as applyPrivacyRemote } from "./privacy";
import { clearDirty as clearDirtyStore, readSettings } from "./security";

// 端云同步：本地永远是权威（离线可用），服务端只作「换机 / 重装恢复」的副本。
// 本地任何变更只置 dirty（模型不发请求）；flush 在 dirty + 有 token 时把当前生效值整体上行，
// 成功且值未再变才清 dirty，在途期间本地又变则保留 dirty 并补发；失败只记日志，下次登录/刷新再试。

let inFlight = false;

const flush = (): void => {
  const settings = readSettings();

  if (inFlight || !settings.dirty || !getTokenBundle()) {
    return;
  }

  inFlight = true;

  const snapshot = {
    privacy_window: settings.privacyWindow,
    app_lock: settings.appLock,
  };

  userApi
    .editConfigMfa(snapshot)
    .then(() => {
      // 先复位单飞标记：下面的补发依赖它
      inFlight = false;

      // 上行期间用户又改过开关：已上行的不是当前值，保留 dirty 并立即补发（dirty 未清，flush 会重新发）
      const current = readSettings();

      if (
        current.privacyWindow === snapshot.privacy_window &&
        current.appLock === snapshot.app_lock
      ) {
        clearDirtyStore();
      } else {
        flush();
      }
    })
    .catch((e: unknown) => {
      inFlight = false;
      logger.warning("安全设置同步失败", e);
    });
};

// 登录后调和（只调一次，不要在每次页面显示时调用）：dirty → 以本地为准上行；
// 否则服务端有值 → 仅应用开关（不置 dirty，恢复用户意愿）；服务端无值 → 保持本地。
const reconcile = async (
  remote: MfaConfigSecurity | null | undefined,
): Promise<void> => {
  if (readSettings().dirty) {
    flush();

    return;
  }

  if (!remote) {
    return;
  }

  // 只恢复 boolean 字段：null/undefined 视为服务端无记录，保持本地
  if (typeof remote.privacy_window === "boolean") {
    await applyPrivacyRemote(remote.privacy_window);
  }

  if (typeof remote.app_lock === "boolean") {
    await applyAppLockRemote(remote.app_lock);
  }
};

// 注销账号：清掉「待上行」语义，避免下一个登录的账号被上一个账号的本地值覆盖
const clearDirty = (): boolean => clearDirtyStore();

export { clearDirty, flush, reconcile };
