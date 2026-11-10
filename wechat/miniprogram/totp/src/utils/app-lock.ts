import { shouldLock } from "./lock-policy";
import logger from "./logger";
import { clearDirty, markDirty, readSettings, writeSettings } from "./security";

// 应用锁：本地设置（appLock）持久化；locked / verifying / generation 等运行态绝不落盘。
export enum VerifyOutcome {
  SUCCESS = "SUCCESS",
  FAILED = "FAILED",
  CANCELED = "CANCELED",
  NO_CREDENTIAL = "NO_CREDENTIAL",
  SKIPPED = "SKIPPED",
}

type SoterAuthMode = "fingerPrint" | "facial";

// --- 运行态（绝不落盘）---
// coldStart 初始 true：模块加载即视为冷启动，避免页面 onShow 早于 App.onLaunch 时漏锁
let locked = false;
let coldStart = true;
let pendingCheck = false;
let lastHideAt: number | undefined;
let verifying = false;
let verifyStartedAt: number | undefined;
let generation = 0;
let lastFinishedAt: number | undefined;

// 3 秒防抖：验证结束后短时间内重复触发直接跳过，避免系统认证控件闪烁
const VERIFY_DEBOUNCE_MS = 3_000;

// 悬挂保险：SOTER 控件异常未回调时 verifying 会一直为 true，用户点解锁永远 SKIPPED（锁死）
const VERIFY_STUCK_MS = 30_000;

const onLaunch = (): void => {
  coldStart = true;
  pendingCheck = false;
  locked = false;
};

const onShow = (): void => {
  pendingCheck = true;
};

const onHide = (): void => {
  lastHideAt = Date.now();
  pendingCheck = false;

  // 真机 SOTER 认证界面会让小程序短暂进入后台（Android 微信为独立认证 Activity，认证结束才回前台）；
  // 此时若作废进行中的验证，用户按完指纹/面容后会被判 SKIPPED，开关页显示「操作过于频繁」（已真机复现）。
  // 真正的离开由 lastHideAt（回前台 60s 判定）与系统自身取消 SOTER（fail）兜底，
  // 因此只作废「空闲代次」，不打断进行中的验证（也不复位 verifying，保持单飞）。
  if (verifying) {
    return;
  }

  generation++;
};

const syncOnPageShow = (): boolean => {
  if (!readSettings().appLock) {
    locked = false;
    pendingCheck = false;

    return false;
  }

  if (locked) {
    pendingCheck = false;

    return true;
  }

  const should = shouldLock({
    enabled: true,
    coldStart,
    // 页面 onShow 可能早于 App.onShow（真机启动 / 回前台时序不确定）：
    // 只要存在退后台时间戳就按时间判定，不依赖 App.onShow 先置 pendingCheck
    pendingCheck: pendingCheck || lastHideAt !== undefined,
    lastHideAt,
    now: Date.now(),
  });

  pendingCheck = false;

  if (should) {
    locked = true;
  } else if (lastHideAt !== undefined) {
    // 本次离开未达 60s：清掉时间戳，避免在同一页面停留后再切页误锁
    lastHideAt = undefined;
  }

  return locked;
};

const isLocked = (): boolean => locked;

const unlock = (): void => {
  locked = false;
  coldStart = false;
  lastHideAt = undefined;
  verifying = false;
  verifyStartedAt = undefined;
  generation++;
};

const setEnabled = (on: boolean): boolean => {
  if (!writeSettings({ ...readSettings(), appLock: on })) {
    return false;
  }

  markDirty();

  if (on) {
    // 复位运行态：否则下一次页面 onShow 仍按「冷启动」立刻上锁
    coldStart = false;
    pendingCheck = false;
    // 刚完成一次身份验证：清掉 SOTER 认证界面触发的退后台时间戳，
    // 避免开启应用锁 60s 后首次切页被误锁
    lastHideAt = undefined;
    locked = false;
  } else {
    unlock();
  }

  return true;
};

// 设备确无凭据降级：只改本机并清 dirty（不回写云端，避免把华为端同字段一起关掉），同时解锁防锁死。
// 不得走 setEnabled(false)——它会 markDirty 导致回写云端。
const disableLocallyNoCredential = (): void => {
  if (!writeSettings({ ...readSettings(), appLock: false })) {
    logger.warning("应用锁本地降级写入失败");
  }

  clearDirty();
  unlock();
};

// 用服务端保存的用户意愿值恢复开关：只改持久化设置，绝不碰 locked（否则登录后会在页面中途凭空弹出遮罩）；
// 不置 dirty。
const applyRemote = async (on: boolean): Promise<void> => {
  if (on && !(await hasCredential())) {
    logger.warning("远端开启应用锁但设备无生物凭据，不落地");

    return;
  }

  writeSettings({ ...readSettings(), appLock: on });
};

// 探测设备可用的已录入生物凭据（fingerPrint/facial）；任何异常都视为无凭据（不抛）。
const probeCredential = async (): Promise<SoterAuthMode | null> => {
  try {
    const res = await wx.checkIsSupportSoterAuthentication();
    const modes = res.supportMode.filter(
      (m): m is SoterAuthMode => m === "fingerPrint" || m === "facial",
    );

    for (const mode of modes) {
      const enrolled = await wx.checkIsSoterEnrolledInDevice({
        checkAuthMode: mode,
      });

      if (enrolled.isEnrolled) {
        return mode;
      }
    }

    return null;
  } catch (e: unknown) {
    logger.warning("探测生物认证凭据失败", e);

    return null;
  }
};

const hasCredential = async (): Promise<boolean> => {
  return (await probeCredential()) !== null;
};

// 随机 challenge：优先 wx.getRandomValues（密码学安全随机数），异常回退非安全随机
const randomChallenge = async (): Promise<string> => {
  try {
    const res = await wx.getRandomValues({ length: 16 });

    return Array.from(new Uint8Array(res.randomValues))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
  } catch {
    return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }
};

// 发起身份认证。不检查 enabled——「开启应用锁」流程需要先验证成功再 setEnabled(true)。
// 单飞 + 3 秒防抖 + 悬挂保险；退后台作废仅发生在「未验证」的空闲态（见 onHide）；
// 不做 resultJSONSignature 签名校验（计划明确，UI 门禁非密码学证明）。
const verify = async (): Promise<VerifyOutcome> => {
  if (verifying) {
    // 悬挂保险：认证已发起但超过阈值仍无回调（SOTER 控件异常），强制复位后继续发起；
    // 旧的悬挂请求若最终返回，会因 generation 变化被判 SKIPPED。
    if (
      verifyStartedAt !== undefined &&
      Date.now() - verifyStartedAt >= VERIFY_STUCK_MS
    ) {
      logger.warning(
        "应用锁验证悬挂超时，强制复位",
        Date.now() - verifyStartedAt,
      );
      verifying = false;
      verifyStartedAt = undefined;
      generation++;
    } else {
      return VerifyOutcome.SKIPPED;
    }
  }

  if (
    lastFinishedAt !== undefined &&
    Date.now() - lastFinishedAt < VERIFY_DEBOUNCE_MS
  ) {
    return VerifyOutcome.SKIPPED;
  }

  const gen = generation;
  verifying = true;
  verifyStartedAt = Date.now();

  try {
    const mode = await probeCredential();

    if (mode === null) {
      // 设备确无凭据：自动解锁 + 本地关闭应用锁（唯一可接受的防锁死路径）
      disableLocallyNoCredential();

      return VerifyOutcome.NO_CREDENTIAL;
    }

    if (gen !== generation) {
      return VerifyOutcome.SKIPPED;
    }

    await wx.startSoterAuthentication({
      requestAuthModes: [mode],
      challenge: await randomChallenge(),
      authContent: "验证身份以解锁",
    });

    if (gen !== generation) {
      return VerifyOutcome.SKIPPED;
    }

    return VerifyOutcome.SUCCESS;
  } catch (e: unknown) {
    if (gen !== generation) {
      return VerifyOutcome.SKIPPED;
    }

    // 用户取消判定：官方 startSoterAuthentication 文档未给出 fail 的 errCode 表，
    // 采用微信 API 通用取消约定（errMsg 含 "cancel"，社区实测 "startSoterAuthentication:fail cancel"）；
    // 其余一律按普通失败处理——CANCELED/FAILED 对状态机影响相同（保持锁定、可重试），仅 UI 文案差异。
    const err = e as { errMsg?: string };

    if ((err.errMsg ?? "").toLowerCase().includes("cancel")) {
      return VerifyOutcome.CANCELED;
    }

    return VerifyOutcome.FAILED;
  } finally {
    // 出口统一复位：任一漏复位会让用户点解锁永远 SKIPPED = 锁死
    verifying = false;
    verifyStartedAt = undefined;
    lastFinishedAt = Date.now();
  }
};

export {
  applyRemote,
  disableLocallyNoCredential,
  hasCredential,
  isLocked,
  onHide,
  onLaunch,
  onShow,
  setEnabled,
  syncOnPageShow,
  unlock,
  verify,
};
