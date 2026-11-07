import { beforeEach, describe, expect, it } from "bun:test";

// wx 最小桩：src/utils/logger.ts 顶层执行 wx.getRealtimeLogManager()，
// 必须先注入 globalThis.wx 再动态 import 被测模块（禁止新建共享 stub 文件，避免并发冲突）。
const storage: Record<string, unknown> = {};
let clipboardFail = false;

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
  showToast: () => undefined,
  setClipboardData: (_option: { data: string }) =>
    new Promise((resolve, reject) => {
      if (clipboardFail) {
        reject(new Error("mock: setClipboardData failed"));

        return;
      }
      resolve({ errMsg: "setClipboardData:ok" });
    }),
};

globalThis.wx = wxStub as unknown as WechatMiniprogram.Wx;

const security = await import("../../src/utils/security");
const userCache = await import("../../src/utils/user-cache");
const clipboard = await import("../../src/utils/clipboard");

beforeEach(() => {
  for (const key of Object.keys(storage)) {
    delete storage[key];
  }
  clipboardFail = false;
});

describe("normalizeSettings", () => {
  it("missingFields_fallBackToDefaults", () => {
    expect(security.normalizeSettings(null)).toEqual(
      security.DEFAULT_SECURITY_SETTINGS,
    );
    expect(security.normalizeSettings(undefined)).toEqual(
      security.DEFAULT_SECURITY_SETTINGS,
    );
    expect(security.normalizeSettings("")).toEqual(
      security.DEFAULT_SECURITY_SETTINGS,
    );
    expect(security.normalizeSettings({})).toEqual(
      security.DEFAULT_SECURITY_SETTINGS,
    );
  });

  it("dirtyData_fallBackToDefaults", () => {
    expect(
      security.normalizeSettings({
        v: 1,
        privacyWindow: "yes",
        appLock: 1,
        dirty: "x",
      }),
    ).toEqual({ v: 1, privacyWindow: true, appLock: false, dirty: false });
  });

  it("versionMismatch_fallBackToDefaults", () => {
    expect(
      security.normalizeSettings({
        v: 2,
        privacyWindow: false,
        appLock: true,
        dirty: true,
      }),
    ).toEqual(security.DEFAULT_SECURITY_SETTINGS);
  });

  it("validSettings_keptAsIs", () => {
    expect(
      security.normalizeSettings({
        v: 1,
        privacyWindow: false,
        appLock: true,
        dirty: true,
      }),
    ).toEqual({ v: 1, privacyWindow: false, appLock: true, dirty: true });
  });

  it("dirtyNotClearedByNormalize", () => {
    expect(
      security.normalizeSettings({
        v: 1,
        privacyWindow: true,
        appLock: false,
        dirty: true,
      }).dirty,
    ).toBe(true);
  });
});

describe("security settings storage", () => {
  it("writeThenRead_roundTrip", () => {
    expect(
      security.writeSettings({
        v: 1,
        privacyWindow: false,
        appLock: true,
        dirty: true,
      }),
    ).toBe(true);
    expect(security.readSettings()).toEqual({
      v: 1,
      privacyWindow: false,
      appLock: true,
      dirty: true,
    });
  });

  it("readWithoutData_returnsDefaults", () => {
    expect(security.readSettings()).toEqual(security.DEFAULT_SECURITY_SETTINGS);
  });

  it("markDirtyAndClearDirty", () => {
    expect(
      security.writeSettings({
        v: 1,
        privacyWindow: false,
        appLock: true,
        dirty: false,
      }),
    ).toBe(true);
    expect(security.markDirty()).toBe(true);
    expect(security.readSettings().dirty).toBe(true);
    expect(security.readSettings().appLock).toBe(true);
    expect(security.clearDirty()).toBe(true);
    expect(security.readSettings().dirty).toBe(false);
  });
});

describe("normalizeUserCache", () => {
  it("nonObject_returnsNull", () => {
    expect(userCache.normalizeUserCache(null)).toBeNull();
    expect(userCache.normalizeUserCache(undefined)).toBeNull();
    expect(userCache.normalizeUserCache("x")).toBeNull();
  });

  it("missingOrInvalidConfig_returnsNull", () => {
    expect(userCache.normalizeUserCache({ phone: "138" })).toBeNull();
    expect(
      userCache.normalizeUserCache({ phone: "138", config: null }),
    ).toBeNull();
  });

  it("emptyStrings_normalizedToUndefined", () => {
    const c = userCache.normalizeUserCache({
      phone: "",
      config: { avatar: "", nickname: "", slogan: "" },
    });
    expect(c).not.toBeNull();

    if (c === null) {
      throw new Error("unreachable");
    }

    expect(c.phone).toBeUndefined();
    expect(c.config.avatar).toBeUndefined();
    expect(c.config.nickname).toBeUndefined();
    expect(c.config.slogan).toBeUndefined();
  });

  it("validCache_keptAsIs", () => {
    const c = userCache.normalizeUserCache({
      phone: "13800138000",
      config: { avatar: "a.png", nickname: "昵称", slogan: "让认证极致简单" },
    });
    expect(c).toEqual({
      phone: "13800138000",
      config: { avatar: "a.png", nickname: "昵称", slogan: "让认证极致简单" },
    });
  });

  it("mfaStripped", () => {
    const c = userCache.normalizeUserCache({
      phone: "13800138000",
      config: {
        nickname: "n",
        mfa: { security: { privacy_window: true, app_lock: true } },
      },
    });
    expect(c).not.toBeNull();

    if (c === null) {
      throw new Error("unreachable");
    }

    expect(c.config.nickname).toBe("n");
    expect("mfa" in c.config).toBe(false);
  });
});

describe("user cache storage", () => {
  it("writeUserCache_stripsMfa", () => {
    expect(
      userCache.writeUserCache({
        phone: "13800138000",
        config: {
          nickname: "n",
          mfa: { security: { privacy_window: true, app_lock: true } },
        },
      }),
    ).toBe(true);
    expect(userCache.readUserCache()).toEqual({
      phone: "13800138000",
      config: { nickname: "n" },
    });
  });

  it("updateUserCache_patchKeepsOthers", () => {
    expect(
      userCache.writeUserCache({
        phone: "13800138000",
        config: { nickname: "n", slogan: "s" },
      }),
    ).toBe(true);
    expect(userCache.updateUserCache({ config: { nickname: "n2" } })).toBe(
      true,
    );
    expect(userCache.readUserCache()).toEqual({
      phone: "13800138000",
      config: { nickname: "n2", slogan: "s" },
    });
  });

  it("clearUserCache_removesKey", () => {
    expect(userCache.writeUserCache({ phone: "13800138000", config: {} })).toBe(
      true,
    );
    userCache.clearUserCache();
    expect(userCache.readUserCache()).toBeNull();
  });
});

describe("clipboard", () => {
  it("copySuccess_returnsTrue", async () => {
    expect(await clipboard.copyText("123456")).toBe(true);
  });

  it("copyFailure_returnsFalse", async () => {
    clipboardFail = true;
    expect(await clipboard.copyText("123456")).toBe(false);
  });
});
