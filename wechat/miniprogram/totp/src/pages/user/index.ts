import userApi from "@api/user";
import { HttpError } from "@models/error";
import { ensureAuthenticated } from "@utils/app";
import {
  syncOnPageShow as appLockSyncOnPageShow,
  setEnabled as setAppLockEnabled,
  VerifyOutcome,
  verify as verifyAppLock,
} from "@utils/app-lock";
import error from "@utils/error";
import { withLoading } from "@utils/loading";
import logger from "@utils/logger";
import {
  isSupported as isPrivacySupported,
  setEnabled as setPrivacyEnabled,
} from "@utils/privacy";
import { readSettings } from "@utils/security";
import { flush as flushSecuritySync } from "@utils/security-sync";
import { readCache } from "@utils/totp-cache";
import { readUserCache, updateUserCache } from "@utils/user-cache";
import { refreshUser } from "@utils/user-sync";
import Message from "tdesign-miniprogram/message/index";
import Toast from "tdesign-miniprogram/toast/index";

interface SwitchChangeEvent {
  detail: { value: boolean };
}

interface ChooseAvatarEvent {
  detail: { avatarUrl: string };
}

interface CanvasNodeResult {
  node?: WechatMiniprogram.Canvas;
}

const buildVersionText = (): string => {
  const { miniProgram } = wx.getAccountInfoSync();
  const envLabel =
    miniProgram.envVersion === "develop"
      ? "开发版"
      : miniProgram.envVersion === "trial"
        ? "体验版"
        : "正式版";
  // 开发版（IDE / 真机调试）取不到上传版本号，只展示环境标签，避免出现 v0.0.0
  const version = (miniProgram.version || "").trim();

  return version.length > 0 ? `v${version}（${envLabel}）` : envLabel;
};

const appLockOutcomeMessage = (outcome: VerifyOutcome): string => {
  switch (outcome) {
    case VerifyOutcome.NO_CREDENTIAL:
      return "设备未录入指纹或面容，无法开启应用锁";
    case VerifyOutcome.CANCELED:
      return "已取消验证，应用锁未开启";
    case VerifyOutcome.FAILED:
      return "验证失败，请重试";
    case VerifyOutcome.SKIPPED:
      return "操作过于频繁，请稍后再试";
    default:
      return "";
  }
};

// 读取文件 base64：typings 5.3.1 未将 readFile 声明为 Promise 风格（运行时支持），显式包装
const readBase64 = (filePath: string): Promise<string> => {
  return new Promise((resolve, reject) => {
    wx.getFileSystemManager().readFile({
      filePath,
      encoding: "base64",
      success: (res) => {
        resolve(typeof res.data === "string" ? res.data : "");
      },
      fail: (err) => {
        reject(new Error(err.errMsg || "readFile failed"));
      },
    });
  });
};

Page({
  data: {
    locked: false,
    avatar: "",
    nickname: "",
    slogan: "",
    protectedCount: 0,
    privacyWindow: true,
    appLock: false,
    securityRevision: 0,
    versionText: "",
  },
  uploadingAvatar: false,
  async onShow() {
    // 应用锁守卫：锁定时不发请求，直接渲染遮罩
    const locked = appLockSyncOnPageShow();

    if (locked !== this.data.locked) {
      this.setData({ locked });
    }

    if (locked) {
      return;
    }

    await ensureAuthenticated().catch(() => undefined);

    // refreshUser 内部已捕获异常，失败静默；资料以本地缓存兜底展示
    await refreshUser();

    const settings = readSettings();
    const user = readUserCache();
    const cache = readCache();

    this.setData({
      privacyWindow: settings.privacyWindow,
      appLock: settings.appLock,
      protectedCount: cache?.items.length ?? 0,
      avatar: user?.config.avatar ?? "",
      nickname: user?.config.nickname ?? "",
      slogan: user?.config.slogan ?? "",
      versionText: buildVersionText(),
    });
  },
  // 解锁成功：解除锁定并重新执行 onShow（重新拉取资料与安全设置）
  onUnlocked() {
    this.setData({ locked: false });
    this.onShow();
  },
  async gotoNickname() {
    await wx.navigateTo({ url: "/pages/user/nickname/index" });
  },
  async gotoSlogan() {
    await wx.navigateTo({ url: "/pages/user/slogan/index" });
  },
  async gotoHelp() {
    await wx.navigateTo({ url: "/pages/help/index" });
  },
  async gotoBackup() {
    await wx.navigateTo({ url: "/pages/backup/index" });
  },
  async gotoDelete() {
    await wx.navigateTo({ url: "/pages/user/delete/index" });
  },
  onAvatarError() {
    // 头像 URL 加载失败（如域名未配置微信白名单）：回落默认图标
    this.setData({ avatar: "" });
  },
  async onChooseAvatar(e: ChooseAvatarEvent) {
    const tempPath = e.detail.avatarUrl;

    if (tempPath.length === 0) {
      return;
    }

    if (this.uploadingAvatar) {
      return;
    }

    this.uploadingAvatar = true;

    let dataUri: string;

    try {
      // 转码 + 上传整体出「处理中」，避免 PNG 大图转码期间无反馈
      dataUri = await withLoading("处理中...", async () => {
        const converted = await this.avatarToJpegDataUri(tempPath);

        await userApi.editAvatar(converted);

        return converted;
      });
    } catch (err) {
      this.uploadingAvatar = false;

      if (err instanceof HttpError) {
        // 失败保持原头像
        Message.error({
          content: `头像更新失败：${error.getErrorMessage(err)}`,
          duration: 5000,
          offset: [20, 32],
          context: this,
        });
      } else {
        logger.warning("头像读取失败", err);
        Message.error({
          content: "头像读取失败，请重试",
          duration: 5000,
          offset: [20, 32],
          context: this,
        });
      }

      return;
    }

    this.uploadingAvatar = false;
    updateUserCache({ config: { avatar: dataUri } });
    this.setData({ avatar: dataUri });

    Toast({
      message: "头像已更新",
      theme: "success",
      duration: 1500,
      direction: "column",
    });
  },
  async avatarToJpegDataUri(tempPath: string): Promise<string> {
    const ext = tempPath.split(".").pop()?.toLowerCase() ?? "";

    // PNG 走隐藏 canvas 2D 转 256×256 JPEG；其余（jpg/jpeg 等）直接按 JPEG base64 上传
    if (ext === "png") {
      return this.pngToJpegDataUri(tempPath);
    }

    const base64 = await readBase64(tempPath);

    if (base64.length === 0) {
      throw new Error("头像文件为空");
    }

    return `data:image/jpeg;base64,${base64}`;
  },
  pngToJpegDataUri(tempPath: string): Promise<string> {
    return new Promise((resolve, reject) => {
      wx.createSelectorQuery()
        .select("#avatar-canvas")
        .fields({ node: true, size: true })
        .exec((res) => {
          const info = (res?.[0] ?? {}) as CanvasNodeResult;
          const canvas = info.node;

          if (typeof canvas === "undefined") {
            reject(new Error("头像转码 canvas 不可用"));

            return;
          }

          canvas.width = 256;
          canvas.height = 256;

          const ctx = canvas.getContext("2d");
          const image = canvas.createImage();

          image.onload = () => {
            try {
              ctx.drawImage(image, 0, 0, 256, 256);
              resolve(canvas.toDataURL("image/jpeg", 0.8));
            } catch (err) {
              reject(err instanceof Error ? err : new Error("头像转码失败"));
            }
          };
          image.onerror = () => {
            reject(new Error("头像图片加载失败"));
          };
          image.src = tempPath;
        });
    });
  },
  onPrivacyChange(e: SwitchChangeEvent) {
    const next = e.detail.value === true;

    if (next && !isPrivacySupported()) {
      Message.error({
        content: "当前设备或基础库不支持防截屏",
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    } else if (!setPrivacyEnabled(next)) {
      Message.error({
        content: "防截屏设置保存失败",
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    } else {
      flushSecuritySync();
      this.setData({ privacyWindow: next });

      return;
    }

    // 回滚视觉：递增 revision 切换 wx:if 奇偶分支，强制重建开关（保持旧值）
    this.setData({ securityRevision: this.data.securityRevision + 1 });
  },
  async onAppLockChange(e: SwitchChangeEvent) {
    const next = e.detail.value === true;

    if (!next) {
      if (setAppLockEnabled(false)) {
        flushSecuritySync();
        this.setData({ appLock: false });

        return;
      }

      Message.error({
        content: "应用锁关闭失败，请重试",
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
      this.setData({ securityRevision: this.data.securityRevision + 1 });

      return;
    }

    const outcome = await verifyAppLock();

    if (outcome === VerifyOutcome.SUCCESS) {
      if (setAppLockEnabled(true)) {
        flushSecuritySync();
        this.setData({ appLock: true });

        return;
      }

      Message.error({
        content: "应用锁开启失败，请重试",
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    } else {
      Message.error({
        content: appLockOutcomeMessage(outcome),
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    }

    this.setData({ securityRevision: this.data.securityRevision + 1 });
  },
});
