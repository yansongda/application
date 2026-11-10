import { afterAll, beforeEach, describe, expect, it } from "bun:test";
import { STORAGE } from "../../src/constant/app";

// wx 最小桩：src/utils/logger.ts 顶层执行 wx.getRealtimeLogManager()，
// 必须先注入 globalThis.wx 再动态 import 被测模块（与 tests/mfa/security.test.ts 同形态）。
// 本文件只测 verify 状态机，不落盘、不发请求。
const storage: Record<string, unknown> = {};

let supportMode: string[] = ["fingerPrint"];
let enrolled = true;
let authImpl: () => Promise<unknown> = async () => ({
  errMsg: "startSoterAuthentication:ok",
});

const wxStub = {
  getRealtimeLogManager: () => ({
    info: () => undefined,
    warn: () => undefined,
    error: () => undefined,
  }),
  getStorageSync: (key: string) => storage[key],
  setStorageSync: (key: string, value: unknown) => {
    storage[key] = value;
  },
  removeStorageSync: (key: string) => {
    delete storage[key];
  },
  checkIsSupportSoterAuthentication: async () => ({ supportMode }),
  checkIsSoterEnrolledInDevice: async () => ({ isEnrolled: enrolled }),
  getRandomValues: async ({ length }: { length: number }) => ({
    randomValues: new Uint8Array(length),
  }),
  startSoterAuthentication: () => authImpl(),
};

globalThis.wx = wxStub as unknown as WechatMiniprogram.Wx;

// 时间可控：app-lock 的防抖 / 悬挂保险都基于 Date.now，逐个用例推进虚构时钟。
const realDateNow = Date.now;
let fakeNow = 1_700_000_000_000;

const appLock = await import("../../src/utils/app-lock");
const { VerifyOutcome } = appLock;

// 让出微任务队列，等 verify 真正进入 SOTER 调用（probe + challenge 共 3 次 await）
const tick = (): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

beforeEach(() => {
  // 推进超过 3 秒防抖窗口，避免用例之间互相污染（lastFinishedAt 无公开复位入口）
  fakeNow += 10_000;
  Date.now = () => fakeNow;

  for (const key of Object.keys(storage)) {
    delete storage[key];
  }

  supportMode = ["fingerPrint"];
  enrolled = true;
  authImpl = async () => ({ errMsg: "startSoterAuthentication:ok" });

  // unlock 是唯一公开的运行态复位入口（locked / coldStart / lastHideAt / verifying / verifyStartedAt）
  appLock.unlock();
  appLock.onLaunch();
  appLock.onShow();
});

afterAll(() => {
  Date.now = realDateNow;
});

describe("app-lock verify", () => {
  it("successOnNormalAuth", async () => {
    expect(await appLock.verify()).toBe(VerifyOutcome.SUCCESS);
  });

  it("onHideDuringAuthDoesNotCancelVerify", async () => {
    // 真机复现：Android 微信 SOTER 认证界面（独立 Activity）会让小程序触发 App.onHide，
    // 修复前 generation++ 把「验证成功」判成 SKIPPED（开关页提示「操作过于频繁」）
    authImpl = async () => {
      appLock.onHide();

      return { errMsg: "startSoterAuthentication:ok" };
    };

    expect(await appLock.verify()).toBe(VerifyOutcome.SUCCESS);
  });

  it("onHideKeepsSingleFlightWhileVerifying", async () => {
    let release: () => void = () => undefined;

    authImpl = () =>
      new Promise((resolve) => {
        release = () => resolve({ errMsg: "startSoterAuthentication:ok" });
      });

    const first = appLock.verify();

    await tick();
    appLock.onHide();
    expect(await appLock.verify()).toBe(VerifyOutcome.SKIPPED);

    release();
    expect(await first).toBe(VerifyOutcome.SUCCESS);
  });

  it("idleOnHideDoesNotBreakNextVerify", async () => {
    // 空闲态退后台仍作废代次（generation++），下一次 verify 捕获新代次后照常成功
    appLock.onHide();
    expect(await appLock.verify()).toBe(VerifyOutcome.SUCCESS);
  });

  it("debouncesWithinThreeSeconds", async () => {
    expect(await appLock.verify()).toBe(VerifyOutcome.SUCCESS);
    expect(await appLock.verify()).toBe(VerifyOutcome.SKIPPED);
  });

  it("returnsCanceledWhenUserCancels", async () => {
    authImpl = async () => {
      throw { errMsg: "startSoterAuthentication:fail cancel" };
    };

    expect(await appLock.verify()).toBe(VerifyOutcome.CANCELED);
  });

  it("returnsFailedOnOtherAuthErrors", async () => {
    authImpl = async () => {
      throw { errMsg: "startSoterAuthentication:fail system error" };
    };

    expect(await appLock.verify()).toBe(VerifyOutcome.FAILED);
  });

  it("degradesWhenNoCredential", async () => {
    supportMode = [];

    expect(await appLock.verify()).toBe(VerifyOutcome.NO_CREDENTIAL);
    // 降级只改本机并清 dirty（不回写云端，避免把华为端同字段一起关掉）
    expect(storage[STORAGE.SECURITY_SETTINGS]).toMatchObject({
      v: 1,
      appLock: false,
      dirty: false,
    });
  });

  it("recoversFromStuckVerify", async () => {
    // SOTER 控件异常、promise 永不 settle：verifying 卡在 true，必须由悬挂保险复位
    authImpl = () => new Promise(() => undefined);

    const hanging = appLock.verify();

    await tick();
    expect(await appLock.verify()).toBe(VerifyOutcome.SKIPPED);

    fakeNow += 31_000;
    authImpl = async () => ({ errMsg: "startSoterAuthentication:ok" });

    expect(await appLock.verify()).toBe(VerifyOutcome.SUCCESS);
    expect(hanging).toBeInstanceOf(Promise);
  });
});

// 页面 onShow 的锁定判定：真机上页面 onShow 可能早于 App.onLaunch / App.onShow，
// 判定不得依赖 App 生命周期先置位（coldStart 初始 true + lastHideAt 时间戳兜底）。
describe("app-lock syncOnPageShow", () => {
  const enableInStorage = (appLockOn: boolean): void => {
    storage[STORAGE.SECURITY_SETTINGS] = {
      v: 1,
      privacyWindow: true,
      appLock: appLockOn,
      dirty: false,
    };
  };

  it("coldStartLocksFirstPageShowWithoutAppOnShow", () => {
    enableInStorage(true);
    appLock.unlock();
    appLock.onLaunch();

    // 不调用 App.onShow（pendingCheck 未置位）也必须锁
    expect(appLock.syncOnPageShow()).toBe(true);
  });

  it("locksAfterBackgroundBeyondTimeoutWithoutAppOnShow", () => {
    enableInStorage(true);
    appLock.unlock();
    appLock.onHide();
    fakeNow += 61_000;

    // 模拟页面 onShow 早于 App.onShow：pendingCheck 仍为 false
    expect(appLock.syncOnPageShow()).toBe(true);
  });

  it("doesNotLockWithinTimeoutAndStopsTimer", () => {
    enableInStorage(true);
    appLock.unlock();
    appLock.onHide();
    fakeNow += 30_000;

    expect(appLock.syncOnPageShow()).toBe(false);

    // 回前台未达阈值：本次离开结束，同页再停留 31s 后切页不得误锁
    fakeNow += 31_000;

    expect(appLock.syncOnPageShow()).toBe(false);
  });

  it("setEnabledClearsSoterHideTimestamp", () => {
    enableInStorage(true);
    appLock.unlock();
    appLock.onLaunch();

    // 开启流程中 SOTER 认证界面触发 onHide（记录退后台时间但作废验证）
    appLock.onHide();
    expect(appLock.setEnabled(true)).toBe(true);

    fakeNow += 61_000;

    // 刚完成身份验证：切页不得因 SOTER 期间的时间戳被误锁
    expect(appLock.syncOnPageShow()).toBe(false);
  });

  it("disabledNeverLocks", () => {
    enableInStorage(false);

    expect(appLock.syncOnPageShow()).toBe(false);
  });

  it("disabledPageShowKeepsColdStartUntilSecurityRestored", () => {
    // 新装/重装：本地 security_settings 被清空（beforeEach 已清 storage）
    appLock.unlock();
    appLock.onLaunch();

    // 首页首次显示：appLock=false → 不锁，但不得消费 coldStart
    expect(appLock.syncOnPageShow()).toBe(false);

    // 登录后 reconcile 从服务端恢复 appLock=true，首页复核必须锁
    enableInStorage(true);

    expect(appLock.syncOnPageShow()).toBe(true);
  });
});
