import accessToken from "@api/access-token";
import { STORAGE } from "@constant/app";
import type { LoginRefreshResponse, LoginResponse } from "types/access-token";

interface StoredBundle extends LoginResponse {
  expired_at: number;
}

const FRESHNESS_BUFFER_MS = 60_000;

/**
 * Wraps wx.login in a Promise. Resolves with the login code.
 */
const wxLogin = (): Promise<string> => {
  return new Promise((resolve, reject) => {
    wx.login({
      success(res) {
        if (res.code) {
          resolve(res.code);
        } else {
          reject(new Error("wx.login returned empty code"));
        }
      },
      fail(err) {
        reject(new Error(err.errMsg || "wx.login failed"));
      },
    });
  });
};

/**
 * Reads and parses the token bundle from storage.
 */
const getTokenBundle = (): LoginResponse | null => {
  const raw = wx.getStorageSync(STORAGE.TOKEN_BUNDLE) as
    | StoredBundle
    | undefined
    | "";

  if (!raw || typeof raw !== "object" || !raw.access_token) {
    return null;
  }

  return {
    access_token: raw.access_token,
    refresh_token: raw.refresh_token,
    expired_in: raw.expired_in,
  };
};

/**
 * Returns the stored bundle with expired_at, or null.
 */
const getStoredBundle = (): StoredBundle | null => {
  const raw = wx.getStorageSync(STORAGE.TOKEN_BUNDLE) as
    | StoredBundle
    | undefined
    | "";

  if (!raw || typeof raw !== "object" || !raw.access_token) {
    return null;
  }

  return raw;
};

/**
 * Checks whether the stored access token is still fresh (not expiring within 60s).
 */
const isAccessTokenFresh = (): boolean => {
  const bundle = getStoredBundle();

  if (!bundle?.access_token || !bundle?.refresh_token || !bundle?.expired_at) {
    return false;
  }

  return Date.now() < bundle.expired_at - FRESHNESS_BUFFER_MS;
};

/**
 * Persists the token bundle to storage. Resolves after write completes.
 */
const saveTokenBundle = (response: LoginResponse): Promise<void> => {
  const expired_at = Date.now() + response.expired_in * 1000;

  wx.setStorageSync(STORAGE.TOKEN_BUNDLE, {
    access_token: response.access_token,
    refresh_token: response.refresh_token,
    expired_in: response.expired_in,
    expired_at,
  } as StoredBundle);

  return Promise.resolve();
};

/**
 * Removes the token bundle from storage.
 */
const clearTokenBundle = (): void => {
  wx.removeStorageSync(STORAGE.TOKEN_BUNDLE);
};

/**
 * Calls the login API with wx.login code and persists the result.
 */
const loginAndSaveToken = async (): Promise<void> => {
  const code = await wxLogin();
  const response = await accessToken.login(code);

  await saveTokenBundle(response);
};

/**
 * Calls the refresh API with the stored refresh_token and persists the result.
 */
const refreshToken = async (): Promise<LoginRefreshResponse> => {
  const bundle = getTokenBundle();

  if (!bundle?.refresh_token) {
    throw new Error("No refresh token available");
  }

  const response = await accessToken.refresh(bundle.refresh_token);

  await saveTokenBundle(response);

  return response;
};

// --- Single-flight auth gate ---

let authPromise: Promise<void> | null = null;

/**
 * Ensures the user is authenticated. Uses a single-flight pattern:
 * if an auth attempt is already in progress, returns the same promise.
 *
 * Resolution order:
 * 1. Fresh access token — resolve immediately
 * 2. Refresh token — refresh and resolve
 * 3. Full login — wx.login + API login + save
 *
 * Rejects on unrecoverable failure so the caller can show an error state.
 */
const ensureAuthenticated = (): Promise<void> => {
  if (authPromise) {
    return authPromise;
  }

  authPromise = (async () => {
    // 1. Already have a fresh token?
    if (isAccessTokenFresh()) {
      return;
    }

    // 2. Try refresh with existing token
    const bundle = getTokenBundle();

    if (bundle?.refresh_token) {
      try {
        await refreshToken();
        return;
      } catch {
        // Refresh failed — fall through to full login
        clearTokenBundle();
      }
    } else {
      clearTokenBundle();
    }

    // 3. Full login flow
    await loginAndSaveToken();
  })().finally(() => {
    authPromise = null;
  });

  return authPromise;
};

export {
  clearTokenBundle,
  ensureAuthenticated,
  getTokenBundle,
  isAccessTokenFresh,
  loginAndSaveToken,
  refreshToken,
  saveTokenBundle,
  wxLogin,
};
