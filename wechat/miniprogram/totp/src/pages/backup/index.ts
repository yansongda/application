/**
 * 导入 / 导出页：加解密全部由服务端完成。
 * - 导出：POST /api/v1/backup/export → 信封 JSON → 保存 / 转发 / 复制
 * - 导入：预检信封 → POST /api/v1/backup/import（批量写入，不去重）
 * 口令只存在于页面内存与请求体：onHide/onUnload 立即清空，不写 storage、不进日志。
 */
import backupApi from "@api/backup";
import { CLIPBOARD_MAX_CHARS, MAX_ITEMS } from "@constant/backup";
import {
  buildExport,
  checkExportPassword,
  checkImportPassword,
  parseEnvelope,
} from "@models/backup";
import { ensureAuthenticated } from "@utils/app";
import {
  syncOnPageShow as appLockSyncOnPageShow,
  VerifyOutcome,
  verify as verifyAppLock,
} from "@utils/app-lock";
import {
  buildBackupFileName,
  readBackupFileFromChat,
  shareBackupFile,
  writeBackupFile,
} from "@utils/backup-file";
import { copyText, readText } from "@utils/clipboard";
import { formatLocalDateTime } from "@utils/datetime";
import error from "@utils/error";
import logger from "@utils/logger";
import { readCache, syncFromRemote } from "@utils/totp-cache";
import Message from "tdesign-miniprogram/message/index";
import Toast from "tdesign-miniprogram/toast/index";
import type { BackupEnvelope } from "types/backup";

interface InputEvent {
  detail: {
    value: string;
  };
}

interface BackupPageData {
  locked: boolean;
  mode: "both" | "import";
  itemsCount: number;
  maxItems: number;
  exportPassword: string;
  exportPasswordConfirm: string;
  exportReady: boolean;
  exportMeta: string;
  exportClipboardAllowed: boolean;
  importReady: boolean;
  importMeta: string;
  importPassword: string;
  importCount: number;
  summary: string;
}

type ImportChannel = "clipboard" | "file";

const appLockMessage = (outcome: VerifyOutcome): string => {
  switch (outcome) {
    case VerifyOutcome.SKIPPED:
      return "身份验证未完成，请 3 秒后重试";
    case VerifyOutcome.CANCELED:
      return "已取消身份验证";
    case VerifyOutcome.FAILED:
      return "身份验证失败，请重试";
    default:
      return "";
  }
};

Page({
  data: {
    locked: false,
    mode: "both" as BackupPageData["mode"],
    itemsCount: 0,
    maxItems: MAX_ITEMS,
    exportPassword: "",
    exportPasswordConfirm: "",
    exportReady: false,
    exportMeta: "",
    exportClipboardAllowed: true,
    importReady: false,
    importMeta: "",
    importPassword: "",
    importCount: 0,
    summary: "",
  } as BackupPageData,
  exportText: "",
  exportFileName: "",
  importEnvelope: undefined as BackupEnvelope | undefined,
  importChannel: "file" as ImportChannel,
  busy: false,

  onLoad(options?: { mode?: string }) {
    if (options?.mode === "import") {
      this.setData({ mode: "import" });
    }
  },

  async onShow() {
    const locked = appLockSyncOnPageShow();

    this.setData({ locked });

    if (locked) {
      this.clearSecrets();

      return;
    }

    await ensureAuthenticated().catch(() => undefined);

    const cache = readCache();

    if (this.data.itemsCount !== (cache?.items.length ?? 0)) {
      this.setData({ itemsCount: cache?.items.length ?? 0 });
    }
  },

  onHide() {
    this.clearSecrets();
  },

  onUnload() {
    this.clearSecrets();
  },

  onUnlocked() {
    this.setData({ locked: false });
    this.onShow();
  },

  clearSecrets() {
    this.setData({
      exportPassword: "",
      exportPasswordConfirm: "",
      exportReady: false,
      exportMeta: "",
      exportClipboardAllowed: true,
      importPassword: "",
    });
    this.exportText = "";
  },

  onExportPasswordChange(e: InputEvent) {
    this.setData({ exportPassword: e.detail.value });
  },

  onExportPasswordConfirmChange(e: InputEvent) {
    this.setData({ exportPasswordConfirm: e.detail.value });
  },

  onImportPasswordChange(e: InputEvent) {
    this.setData({ importPassword: e.detail.value });
  },

  // 导出：确认（含不可恢复警告）→ 应用锁门禁 → 口令强度 → 服务端加密
  async onExport() {
    if (this.busy) {
      return;
    }

    const cache = readCache();

    if (cache === null || cache.items.length === 0) {
      Message.warning({
        content: "没有可导出的账号",
        duration: 3000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    // 服务端以数据库为准；本地缓存超限时提前拦截，给出一致文案
    if (cache.items.length > MAX_ITEMS) {
      Message.warning({
        content: `单次最多导出 ${MAX_ITEMS} 个账号，请先删除多余账号`,
        duration: 3000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    const confirmed = await new Promise<boolean>((resolve) => {
      wx.showModal({
        title: "导出加密备份",
        content: `将导出 ${cache.items.length} 个账号。备份由服务端加密，请牢记口令：忘记口令将无法恢复。`,
        confirmText: "继续",
        success: (res) => resolve(res.confirm === true),
        fail: () => resolve(false),
      });
    });

    if (!confirmed) {
      return;
    }

    const outcome = await verifyAppLock();

    // 门禁映射：SKIPPED 必须拒绝，NO_CREDENTIAL 视为系统已关闭应用锁
    if (
      outcome !== VerifyOutcome.SUCCESS &&
      outcome !== VerifyOutcome.NO_CREDENTIAL
    ) {
      Message.warning({
        content: appLockMessage(outcome) || "身份验证失败，请重试",
        duration: 3000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    const password = this.data.exportPassword;

    const strength = checkExportPassword(
      password,
      this.data.exportPasswordConfirm,
    );

    if (!strength.ok) {
      Message.warning({
        content: strength.reason,
        duration: 3000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    this.busy = true;
    const startedAt = Date.now();

    wx.showLoading({ title: "正在加密...", mask: true });

    try {
      const result = await buildExport(backupApi, password);

      this.exportText = result.text;
      this.exportFileName = buildBackupFileName();

      const clipboardAllowed = result.text.length <= CLIPBOARD_MAX_CHARS;

      this.setData({
        exportReady: true,
        exportMeta: `已加密 ${result.count} 条 · 备份时间 ${formatLocalDateTime(result.createdAt)}`,
        exportClipboardAllowed: clipboardAllowed,
      });

      logger.info("backup_export", {
        channel: "generate",
        count: result.count,
        elapsedMs: Date.now() - startedAt,
      });

      Toast({
        message: "加密备份已生成",
        theme: "success",
        duration: 1500,
        direction: "column",
      });
    } catch (e: unknown) {
      logger.error("backup_error", {
        stage: "export",
        name: (e as Error)?.name,
      });
      Message.error({
        content: error.getErrorMessage(e),
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    } finally {
      wx.hideLoading();
      this.busy = false;
    }
  },

  // 保存并用“转发文件到聊天”（必须用户点击触发）
  async onSaveFile() {
    if (this.exportText.length === 0) {
      return;
    }

    try {
      const file = writeBackupFile(this.exportText, this.exportFileName);

      await shareBackupFile(file);
    } catch (_e: unknown) {
      logger.warning("backup_export", { channel: "file", result: "failed" });
      Message.error({
        content: "发送文件失败，可尝试复制到剪贴板",
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    }
  },

  async onCopyExport() {
    if (this.exportText.length === 0) {
      return;
    }

    const ok = await copyText(this.exportText, "加密备份已复制");

    if (ok) {
      logger.info("backup_export", {
        channel: "clipboard",
        count: this.data.itemsCount,
      });
      Message.info({
        content: "导入完成后请清理剪贴板",
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    }
  },

  // 导入第一步：只做结构预检（不索要口令）
  acceptImportText(text: string, channel: ImportChannel) {
    try {
      const envelope = parseEnvelope(text);

      this.importEnvelope = envelope;
      this.importChannel = channel;

      this.setData({
        importReady: true,
        importMeta: `含 ${envelope.meta.count} 条，导出于 ${formatLocalDateTime(envelope.meta.created_at)}（本地时间）`,
        importCount: envelope.meta.count,
        summary: "",
      });
    } catch (e: unknown) {
      Message.error({
        content: error.getErrorMessage(e),
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    }
  },

  async onPasteImport() {
    const text = await readText();

    if (text === undefined || text.trim().length === 0) {
      Message.warning({
        content: "剪贴板没有内容",
        duration: 3000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    this.acceptImportText(text, "clipboard");
  },

  async onChooseFile() {
    try {
      const file = await readBackupFileFromChat();

      if (file === undefined) {
        return;
      }

      this.acceptImportText(file.text, "file");
    } catch (_e: unknown) {
      logger.warning("backup_parse", { channel: "file", result: "failed" });
      Message.error({
        content: "读取文件失败",
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    }
  },

  // 导入第二步：一次请求交给服务端解密并批量写入；不去重、非事务
  async onStartImport() {
    const envelope = this.importEnvelope;

    if (envelope === undefined || this.busy) {
      return;
    }

    const strength = checkImportPassword(this.data.importPassword);

    if (!strength.ok) {
      Message.warning({
        content: strength.reason,
        duration: 3000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    this.busy = true;
    const startedAt = Date.now();

    wx.showLoading({ title: "正在导入...", mask: true });

    try {
      const report = await backupApi.importBackup(
        envelope,
        this.data.importPassword,
      );

      logger.info("backup_import", {
        channel: this.importChannel,
        imported: report,
        elapsedMs: Date.now() - startedAt,
      });

      // 服务端为准刷新本地缓存与列表
      await syncFromRemote().catch(() => undefined);

      const cache = readCache();

      this.setData({
        itemsCount: cache?.items.length ?? this.data.itemsCount,
        importReady: false,
        importMeta: "",
        importPassword: "",
        importCount: 0,
        summary: `成功导入 ${report} 条`,
      });
      this.importEnvelope = undefined;

      Toast({
        message: `成功导入 ${report} 条`,
        theme: "success",
        duration: 2500,
        direction: "column",
      });
    } catch (e: unknown) {
      logger.error("backup_error", {
        stage: "import",
        name: (e as Error)?.name,
      });
      Message.error({
        content: error.getErrorMessage(e),
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    } finally {
      wx.hideLoading();
      this.busy = false;
    }
  },
});
