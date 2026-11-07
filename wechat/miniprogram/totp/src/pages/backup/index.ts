/**
 * 导入 / 导出页：导出为口令加密的 .mfa（文件转发 / 剪贴板），从任一端备份导入。
 * 口令只存在于页面内存：onHide/onUnload 立即清空，不写 storage、不进日志。
 */
import api from "@api/totp";
import { ensureAuthenticated } from "@utils/app";
import {
  syncOnPageShow as appLockSyncOnPageShow,
  VerifyOutcome,
  verify as verifyAppLock,
} from "@utils/app-lock";
import {
  buildBackupFileName,
  readBackupFileFromChat,
  secureRandom,
  shareBackupFile,
  writeBackupFile,
} from "@utils/backup-file";
import { copyText, readText } from "@utils/clipboard";
import logger from "@utils/logger";
import { readCache, syncFromRemote, upsertItem } from "@utils/totp-cache";
import Message from "tdesign-miniprogram/message/index";
import Toast from "tdesign-miniprogram/toast/index";
import { checkPasswordStrength } from "../../backup/crypto";
import { buildExport } from "../../backup/exporter";
import { analyze, type ImportPlan, precheck, run } from "../../backup/importer";
import { BackupError, backupErrorMessage } from "../../backup/spec";
import type { CacheItem, Item } from "../../types/totp";

interface InputEvent {
  detail: {
    value: string;
  };
}

interface BackupPageData {
  locked: boolean;
  mode: "both" | "import";
  itemsCount: number;
  exportPassword: string;
  exportPasswordConfirm: string;
  exportReady: boolean;
  exportMeta: string;
  exportClipboardAllowed: boolean;
  importReady: boolean;
  importMeta: string;
  importPassword: string;
  planReady: boolean;
  planAccepted: number;
  planDuplicates: number;
  planInvalid: number;
  progressVisible: boolean;
  progressDone: number;
  progressTotal: number;
  progressText: string;
  summary: string;
}

const CLIPBOARD_MAX_ITEMS = 50;
const CLIPBOARD_MAX_BYTES = 65536;

const appVersion = (): string => {
  const { miniProgram } = wx.getAccountInfoSync();

  return miniProgram.version || "0.0.0";
};

const describeError = (e: unknown): string => {
  if (e instanceof BackupError) {
    return e.detail === undefined
      ? backupErrorMessage(e.code)
      : `${backupErrorMessage(e.code)}（${e.detail}）`;
  }

  if (e instanceof Error) {
    return e.message;
  }

  return "操作失败，请重试";
};

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
    exportPassword: "",
    exportPasswordConfirm: "",
    exportReady: false,
    exportMeta: "",
    exportClipboardAllowed: true,
    importReady: false,
    importMeta: "",
    importPassword: "",
    planReady: false,
    planAccepted: 0,
    planDuplicates: 0,
    planInvalid: 0,
    progressVisible: false,
    progressDone: 0,
    progressTotal: 0,
    progressText: "",
    summary: "",
  } as BackupPageData,
  exportText: "",
  exportFileName: "",
  importText: "",
  importFileName: "",
  plan: undefined as ImportPlan | undefined,
  busy: false,
  cancelRequested: false,

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
      importPassword: "",
      progressVisible: false,
      progressText: "",
    });
    this.exportText = "";
    this.importText = "";
    this.plan = undefined;
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

  // 导出前：确认（含不可恢复警告）→ 应用锁门禁 → 口令强度 → 生成密文
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

    const confirmed = await new Promise<boolean>((resolve) => {
      wx.showModal({
        title: "导出加密备份",
        content: `将导出 ${cache.items.length} 个账号。请牢记口令：忘记口令将无法恢复备份。`,
        confirmText: "继续",
        success: (res) => resolve(res.confirm === true),
        fail: () => resolve(false),
      });
    });

    if (!confirmed) {
      return;
    }

    const outcome = await verifyAppLock();

    // 门禁映射（规范 S4）：SKIPPED 必须拒绝，NO_CREDENTIAL 视为系统已关闭应用锁
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

    if (password !== this.data.exportPasswordConfirm) {
      Message.warning({
        content: "两次输入的口令不一致",
        duration: 3000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    const strength = checkPasswordStrength(password);

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
      const result = await buildExport(cache.items, {
        password,
        app: appVersion(),
        rng: secureRandom,
      });

      this.exportText = result.text;
      this.exportFileName = buildBackupFileName();

      const clipboardAllowed =
        result.count <= CLIPBOARD_MAX_ITEMS &&
        result.text.length <= CLIPBOARD_MAX_BYTES;

      this.setData({
        exportReady: true,
        exportMeta: `已加密 ${result.count} 条（跳过 ${result.skipped} 条）`,
        exportClipboardAllowed: clipboardAllowed,
      });

      logger.info("backup_export", {
        channel: "generate",
        count: result.count,
        skipped: result.skipped,
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
        content: describeError(e),
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

  // 导入第一步：只做结构校验（不索要口令）
  acceptImportText(text: string, fileName: string) {
    try {
      const envelope = precheck(text);

      this.importText = text;
      this.importFileName = fileName;
      this.plan = undefined;

      const source =
        envelope.meta.source === "huawei" ? "华为元服务" : "微信小程序";

      this.setData({
        importReady: true,
        importMeta: `来自${source}，含 ${envelope.meta.count} 条，导出于 ${envelope.meta.createdAt}`,
        planReady: false,
        planAccepted: 0,
        planDuplicates: 0,
        planInvalid: 0,
        summary: "",
      });
    } catch (e: unknown) {
      Message.error({
        content: describeError(e),
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

      this.acceptImportText(file.text, file.fileName);
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

  // 导入第二步：解密 + 生成计划（预览 accepted / duplicates / invalid）
  async onAnalyze() {
    if (this.busy || this.importText.length === 0) {
      return;
    }

    const password = this.data.importPassword;

    if (password.length === 0) {
      Message.warning({
        content: "请输入备份口令",
        duration: 3000,
        offset: [20, 32],
        context: this,
      });

      return;
    }

    this.busy = true;
    const startedAt = Date.now();

    wx.showLoading({ title: "正在解密...", mask: true });

    try {
      const cache = readCache();
      const plan = await analyze(this.importText, password, cache?.items ?? []);

      this.plan = plan;

      this.setData({
        planReady: true,
        planAccepted: plan.accepted.length,
        planDuplicates: plan.duplicates,
        planInvalid: plan.invalid.length,
      });

      logger.info("backup_parse", {
        channel: this.importFileName === "clipboard" ? "clipboard" : "file",
        accepted: plan.accepted.length,
        duplicates: plan.duplicates,
        invalid: plan.invalid.length,
        count: plan.envelopeCount,
        elapsedMs: Date.now() - startedAt,
      });
    } catch (e: unknown) {
      logger.error("backup_error", {
        stage: "derive",
        code: (e as BackupError)?.code,
      });
      Message.error({
        content: describeError(e),
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    } finally {
      wx.hideLoading();
      this.busy = false;
    }
  },

  // 导入第三步：串行 create + 校正，可取消；结束后从服务端刷新缓存
  async onStartImport() {
    if (this.plan === undefined || this.busy) {
      return;
    }

    const plan = this.plan;

    if (plan.accepted.length === 0) {
      Toast({
        message: "没有需要导入的账号",
        theme: "success",
        duration: 1500,
        direction: "column",
      });

      return;
    }

    this.busy = true;
    this.cancelRequested = false;
    const startedAt = Date.now();

    this.setData({
      progressVisible: true,
      progressDone: 0,
      progressTotal: plan.accepted.length,
      progressText: `正在导入 0/${plan.accepted.length}`,
      summary: "",
    });

    try {
      const report = await run(plan, {
        api,
        shouldCancel: () => this.cancelRequested,
        onProgress: (done, total) => {
          this.setData({
            progressDone: done,
            progressText: `正在导入 ${done}/${total}`,
          });
        },
        onCreated: (created: Item) => {
          upsertItem({
            id: created.id,
            issuer: created.issuer,
            username: created.username,
            secret: created.config.secret,
            period: created.config.period,
            digits: created.config.digits,
            algorithm: created.config.algorithm,
            tags: created.tags ?? [],
            pinned: created.pinned === true,
          } as CacheItem);
        },
      });

      const summary = [
        `成功 ${report.done} 条`,
        report.failed.length > 0 ? `失败 ${report.failed.length} 条` : "",
        report.canceled ? `未执行 ${report.notExecuted} 条` : "",
      ]
        .filter((part) => part.length > 0)
        .join("，");

      this.setData({ progressVisible: false, summary });

      logger.info("backup_import", {
        done: report.done,
        failed: report.failed.length,
        canceled: report.canceled,
        withTags: report.withTags,
        withPinned: report.withPinned,
        elapsedMs: Date.now() - startedAt,
      });

      // 失败条目不阻塞；以服务端为准刷新本地缓存与列表
      await syncFromRemote().catch(() => undefined);

      const cache = readCache();

      this.setData({
        itemsCount: cache?.items.length ?? this.data.itemsCount,
        planReady: false,
        importReady: false,
        importPassword: "",
      });
      this.plan = undefined;
      this.importText = "";

      Toast({
        message: summary.length > 0 ? summary : "导入完成",
        theme: report.failed.length > 0 ? "warning" : "success",
        duration: 2500,
        direction: "column",
      });
    } catch (e: unknown) {
      logger.error("backup_error", {
        stage: "import",
        name: (e as Error)?.name,
      });
      Message.error({
        content: describeError(e),
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
      this.setData({ progressVisible: false });
    } finally {
      this.busy = false;
    }
  },

  onCancelImport() {
    this.cancelRequested = true;
    this.setData({ progressText: "正在取消..." });
  },
});
