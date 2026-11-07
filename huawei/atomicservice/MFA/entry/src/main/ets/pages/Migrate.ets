// 导入 / 导出页（路由 migrate）：导出为口令加密的 .mfa（文件 / 剪贴板），从任一端备份导入。
// 口令只存在于页面内存：onHidden 立即清空，不写 preferences、不进日志。
import {
  AdvancedDialogV2Button,
  AlertDialogV2,
  AppStorageV2,
  LoadingDialogV2
} from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Totp } from '../api/Totp';
import { IItem } from '../types/Item';
import { App, AppPagesName, LogDomain } from '../App';
import { ExportResult, Exporter } from '../models/backup/Exporter';
import { Importer } from '../models/backup/Importer';
import { ImportPlan, ImportReport } from '../models/backup/ImportTypes';
import { IEnvelope, parseEnvelope } from '../models/backup/Envelope';
import { BackupError, backupErrorText } from '../models/backup/Spec';
import { AppLock, VerifyOutcome } from '../models/security/AppLock';
import { ItemsRuntime } from '../models/totp/ItemsRuntime';
import { Clipboard } from '../utils/Clipboard';
import { FileSaveOutcome, FileTransfer } from '../utils/FileTransfer';
import { Dialog, Toast } from '../utils/PromptAction';

const CLIPBOARD_MAX_ITEMS: number = 50;
const CLIPBOARD_MAX_BYTES: number = 65536;

@Builder
export function builder() {
  Migrate()
}

@ComponentV2
struct Migrate {
  @Local
  private itemsCount: number = 0;
  @Local
  private exportPassword: string = '';
  @Local
  private exportPasswordConfirm: string = '';
  @Local
  private exportReady: boolean = false;
  @Local
  private exportMeta: string = '';
  @Local
  private exportClipboardAllowed: boolean = true;
  @Local
  private importReady: boolean = false;
  @Local
  private importMeta: string = '';
  @Local
  private importPassword: string = '';
  @Local
  private manualText: string = '';
  @Local
  private planReady: boolean = false;
  @Local
  private planAccepted: number = 0;
  @Local
  private planDuplicates: number = 0;
  @Local
  private planInvalid: number = 0;
  @Local
  private progressVisible: boolean = false;
  @Local
  private progressDone: number = 0;
  @Local
  private progressTotal: number = 0;
  @Local
  private progressText: string = '';
  @Local
  private summary: string = '';

  private exportText: string = '';
  private exportFileName: string = '';
  private importText: string = '';
  private plan: ImportPlan | undefined = undefined;
  private busy: boolean = false;
  private cancelRequested: boolean = false;
  private itemsRuntime: ItemsRuntime = AppStorageV2.connect(ItemsRuntime, () => new ItemsRuntime())!;
  private appLock: AppLock = AppLock.instance();

  aboutToAppear(): void {
    this.itemsCount = this.itemsRuntime.ids.length;
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: $r('app.integer.column_space') }) {
          this.exportCard()
          this.importCard()
        }
        .width('100%')
        .padding($r('app.integer.page_padding'))
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .title($r('app.string.backup_page_title'))
    .onShown(() => {
      this.itemsCount = this.itemsRuntime.ids.length;
    })
    .onHidden(() => {
      this.clearSecrets();
    })
  }

  // 导出卡：口令 + 确认 + 生成；生成后可保存文件或复制到剪贴板
  @Builder
  exportCard() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      Text($r('app.string.backup_export_title'))
        .width('100%')
        .fontSize($r('app.float.body_font_size'))
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Start)

      Text($r('app.string.backup_export_desc', this.itemsCount))
        .width('100%')
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Start)

      TextInput({
        placeholder: $r('app.string.backup_export_password_placeholder'),
        text: this.exportPassword
      })
        .type(InputType.Password)
        .maxLength(128)
        .height(44)
        .backgroundColor($r('sys.color.background_secondary'))
        .borderRadius($r('app.integer.card_radius'))
        .onChange((value: string): void => {
          this.exportPassword = value;
        })

      TextInput({
        placeholder: $r('app.string.backup_export_password_confirm_placeholder'),
        text: this.exportPasswordConfirm
      })
        .type(InputType.Password)
        .maxLength(128)
        .height(44)
        .backgroundColor($r('sys.color.background_secondary'))
        .borderRadius($r('app.integer.card_radius'))
        .onChange((value: string): void => {
          this.exportPasswordConfirm = value;
        })

      Button($r('app.string.backup_export_generate'))
        .width('100%')
        .type(ButtonType.Capsule)
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('sys.color.font_on_primary'))
        .onClick(() => {
          this.requestExport();
        })

      if (this.exportReady) {
        Button($r('app.string.backup_export_save'))
          .width('100%')
          .type(ButtonType.Capsule)
          .backgroundColor($r('sys.color.background_secondary'))
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => {
            this.saveExportFile().catch(() => {
              // 失败已由 Toast 提示，仅避免 unhandled rejection
            });
          })

        Button($r('app.string.backup_export_copy'))
          .width('100%')
          .type(ButtonType.Capsule)
          .backgroundColor($r('sys.color.background_secondary'))
          .fontColor($r('sys.color.font_secondary'))
          .enabled(this.exportClipboardAllowed)
          .onClick(() => {
            this.copyExport().catch(() => {
              // 失败已由 Toast 提示，仅避免 unhandled rejection
            });
          })

        Text(this.exportMeta)
          .width('100%')
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('sys.color.font_secondary'))
          .textAlign(TextAlign.Start)
      }

      Text($r('app.string.backup_export_warn'))
        .width('100%')
        .fontSize($r('app.float.caption_smaller_font_size'))
        .fontColor($r('sys.color.font_tertiary'))
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding($r('app.integer.page_padding'))
    .backgroundColor($r('sys.color.background_primary'))
    .borderRadius($r('app.integer.card_radius'))
  }

  // 导入卡：PasteButton / 文件 / 手贴 → 口令 → 预览 → 串行导入（可取消）
  @Builder
  importCard() {
    Column({ space: $r('app.integer.column_space_smaller') }) {
      Text($r('app.string.backup_import_title'))
        .width('100%')
        .fontSize($r('app.float.body_font_size'))
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Start)

      Text($r('app.string.backup_import_desc'))
        .width('100%')
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Start)

      // 安全控件：授权成功后本次读取剪贴板才被系统允许
      PasteButton()
        .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
          this.pasteFromClipboard(result).catch(() => {
            // 失败已由 Toast 提示，仅避免 unhandled rejection
          });
        })

      Button($r('app.string.backup_import_file'))
        .width('100%')
        .type(ButtonType.Capsule)
        .backgroundColor($r('sys.color.background_secondary'))
        .fontColor($r('sys.color.font_secondary'))
        .onClick(() => {
          this.pickBackupFile().catch(() => {
            // 失败已由 Toast 提示，仅避免 unhandled rejection
          });
        })

      TextArea({
        placeholder: $r('app.string.backup_import_manual_placeholder'),
        text: this.manualText
      })
        .height(96)
        .backgroundColor($r('sys.color.background_secondary'))
        .borderRadius($r('app.integer.card_radius'))
        .fontSize($r('app.float.caption_smaller_font_size'))
        .onChange((value: string): void => {
          this.manualText = value;
        })

      Button($r('app.string.backup_import_manual_button'))
        .width('100%')
        .type(ButtonType.Capsule)
        .backgroundColor($r('sys.color.background_secondary'))
        .fontColor($r('sys.color.font_secondary'))
        .onClick(() => {
          this.acceptImportText(this.manualText, 'manual');
        })

      if (this.importReady) {
        Text(this.importMeta)
          .width('100%')
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('sys.color.font_secondary'))
          .textAlign(TextAlign.Start)

        TextInput({
          placeholder: $r('app.string.backup_import_password_placeholder'),
          text: this.importPassword
        })
          .type(InputType.Password)
          .maxLength(128)
          .height(44)
          .backgroundColor($r('sys.color.background_secondary'))
          .borderRadius($r('app.integer.card_radius'))
          .onChange((value: string): void => {
            this.importPassword = value;
          })

        Button($r('app.string.backup_import_analyze'))
          .width('100%')
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('sys.color.font_on_primary'))
          .onClick(() => {
            this.analyzeImport().catch(() => {
              // 失败已由 Toast 提示，仅避免 unhandled rejection
            });
          })
      }

      if (this.planReady) {
        Text($r('app.string.backup_import_plan', this.planAccepted))
          .width('100%')
          .fontSize($r('app.float.caption_font_size'))
          .textAlign(TextAlign.Start)

        if (this.planDuplicates > 0) {
          Text($r('app.string.backup_import_duplicates', this.planDuplicates))
            .width('100%')
            .fontSize($r('app.float.caption_font_size'))
            .fontColor($r('sys.color.font_secondary'))
            .textAlign(TextAlign.Start)
        }

        if (this.planInvalid > 0) {
          Text($r('app.string.backup_import_invalid', this.planInvalid))
            .width('100%')
            .fontSize($r('app.float.caption_font_size'))
            .fontColor($r('sys.color.font_secondary'))
            .textAlign(TextAlign.Start)
        }

        Button($r('app.string.backup_import_start', this.planAccepted))
          .width('100%')
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('sys.color.font_on_primary'))
          .enabled(this.planAccepted > 0)
          .onClick(() => {
            this.startImport().catch(() => {
              // 失败已由 Toast 提示，仅避免 unhandled rejection
            });
          })
      }

      if (this.progressVisible) {
        Column({ space: $r('app.integer.column_space_smaller') }) {
          Progress({
            value: this.progressDone,
            total: this.progressTotal,
            type: ProgressType.Linear
          })
            .width('100%')

          Row({ space: $r('app.integer.column_space_smaller') }) {
            Text(this.progressText)
              .fontSize($r('app.float.caption_font_size'))
              .fontColor($r('sys.color.font_secondary'))
              .layoutWeight(1)

            Button($r('app.string.backup_cancel'))
              .type(ButtonType.Capsule)
              .height(32)
              .fontSize($r('app.float.caption_smaller_font_size'))
              .backgroundColor($r('sys.color.background_secondary'))
              .fontColor($r('sys.color.font_secondary'))
              .onClick(() => {
                this.cancelRequested = true;
                this.progressText = '正在取消...';
              })
          }
          .width('100%')
        }
        .width('100%')
      }

      if (this.summary.length > 0) {
        Text(this.summary)
          .width('100%')
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('sys.color.font_secondary'))
          .textAlign(TextAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding($r('app.integer.page_padding'))
    .backgroundColor($r('sys.color.background_primary'))
    .borderRadius($r('app.integer.card_radius'))
    .margin({ top: $r('app.integer.column_space') })
  }

  @Builder
  loadingDialog() {
    LoadingDialogV2({
      content: $r('app.string.handling')
    })
  }

  @Builder
  confirmExportDialog() {
    AlertDialogV2({
      primaryTitle: $r('app.string.backup_export_confirm_title'),
      content: $r('app.string.backup_export_confirm_content', this.itemsCount),
      primaryButton: new AdvancedDialogV2Button({
        content: $r('app.string.backup_cancel')
      }),
      secondaryButton: new AdvancedDialogV2Button({
        content: $r('app.string.backup_export_continue'),
        action: () => {
          this.performExport().catch(() => {
            // 失败已由 Toast 提示，仅避免 unhandled rejection
          });
        }
      })
    })
  }

  private clearSecrets(): void {
    this.exportPassword = '';
    this.exportPasswordConfirm = '';
    this.importPassword = '';
    this.manualText = '';
    this.exportText = '';
    this.importText = '';
    this.plan = undefined;
    this.progressVisible = false;
    this.progressText = '';
  }

  private currentItems(): IItem[] {
    const items: IItem[] = [];

    for (const id of this.itemsRuntime.ids) {
      const runtime = this.itemsRuntime.get(id);

      if ('undefined' === typeof runtime || runtime.id.length === 0) {
        continue;
      }

      items.push({
        id: runtime.id,
        issuer: runtime.issuer,
        username: runtime.username,
        tags: runtime.tags,
        pinned: runtime.pinned,
        code: 'undefined' === typeof runtime.code ? '' : runtime.code,
        config: runtime.config
      });
    }

    return items;
  }

  private showError(e: Object): void {
    if (e instanceof BackupError) {
      const backupError: BackupError = e as BackupError;

      hilog.warn(LogDomain.PAGES, AppPagesName.MIGRATE, 'backup_error: code=%{public}s', backupError.code.toString());
      Toast.show({ message: backupErrorText(backupError.code), duration: 3000 });

      return;
    }

    const error: Error = e as Error;

    Toast.show({ message: 'undefined' !== typeof error.message ? error.message : '操作失败，请重试', duration: 3000 });
  }

  private isExportClipboardAllowed(count: number, text: string): boolean {
    return count <= CLIPBOARD_MAX_ITEMS && text.length <= CLIPBOARD_MAX_BYTES;
  }

  private backupFileName(): string {
    const now: Date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    const date: string = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}`;
    const time: string = `${pad(now.getHours())}${pad(now.getMinutes())}`;

    return `mfa-backup-${date}-${time}.mfa`;
  }

  private requestExport(): void {
    if (this.busy) {
      return;
    }

    if (this.itemsRuntime.ids.length <= 0) {
      Toast.show({ message: $r('app.string.backup_no_items'), duration: 3000 });

      return;
    }

    Dialog.open(() => this.confirmExportDialog());
  }

  // 导出前门禁（规范 S4）：仅 SUCCESS / NO_CREDENTIAL 放行；SKIPPED 必须拒绝
  private async performExport(): Promise<void> {
    if (this.busy) {
      return;
    }

    const context = this.getUIContext().getHostContext();

    if ('undefined' === typeof context) {
      return;
    }

    const outcome: VerifyOutcome = await new Promise<VerifyOutcome>((resolve: (value: VerifyOutcome) => void) => {
      this.appLock.verify(context, (result: VerifyOutcome): void => {
        resolve(result);
      });
    });

    if (VerifyOutcome.SUCCESS !== outcome && VerifyOutcome.NO_CREDENTIAL !== outcome) {
      const message: Resource | undefined = VerifyOutcome.SKIPPED === outcome ?
        $r('app.string.backup_auth_skipped') :
        (VerifyOutcome.CANCELED === outcome ? $r('app.string.backup_auth_canceled') :
          $r('app.string.backup_auth_failed'));

      Toast.show({ message: message, duration: 3000 });

      return;
    }

    if (this.exportPassword !== this.exportPasswordConfirm) {
      Toast.show({ message: $r('app.string.backup_password_mismatch'), duration: 3000 });

      return;
    }

    this.busy = true;

    try {
      const items: IItem[] = this.currentItems();
      const result: ExportResult = await Dialog.execute(
        () => this.loadingDialog(),
        () => Exporter.build(items, this.exportPassword, App.version)
      );

      this.exportText = result.text;
      this.exportFileName = this.backupFileName();
      this.exportClipboardAllowed = this.isExportClipboardAllowed(result.count, result.text);
      this.exportMeta = `已加密 ${result.count} 条（跳过 ${result.skipped} 条）`;
      this.exportReady = true;

      hilog.info(LogDomain.PAGES, AppPagesName.MIGRATE, 'backup_export: count=%{public}d, skipped=%{public}d',
        result.count, result.skipped);

      Toast.show({ message: $r('app.string.backup_export_generated'), duration: 3000 });
    } catch (e) {
      this.showError(e as Object);
    } finally {
      this.busy = false;
    }
  }

  private async saveExportFile(): Promise<void> {
    if (this.busy || this.exportText.length === 0) {
      return;
    }

    const context = this.getUIContext().getHostContext();

    if ('undefined' === typeof context) {
      return;
    }

    this.busy = true;

    try {
      const outcome: FileSaveOutcome = await FileTransfer.saveText(context, this.exportText, this.exportFileName);

      if (FileSaveOutcome.SAVED === outcome) {
        Toast.show({ message: $r('app.string.backup_saved'), duration: 3000 });
      } else if (FileSaveOutcome.FAILED === outcome) {
        Toast.show({ message: $r('app.string.backup_save_failed'), duration: 3000 });
      }
    } catch (e) {
      this.showError(e as Object);
    } finally {
      this.busy = false;
    }
  }

  private async copyExport(): Promise<void> {
    if (this.exportText.length === 0) {
      return;
    }

    try {
      await Clipboard.copy(this.exportText);

      hilog.info(LogDomain.PAGES, AppPagesName.MIGRATE, 'backup_export: channel=clipboard');

      Toast.show({ message: $r('app.string.backup_copied'), duration: 3000 });
    } catch (e) {
      this.showError(e as Object);
    }
  }

  // 导入第一步：只做结构校验（不索要口令）
  private acceptImportText(text: string, source: string): void {
    if (text.trim().length === 0) {
      Toast.show({ message: $r('app.string.backup_import_empty'), duration: 3000 });

      return;
    }

    const parsed = parseEnvelope(text);

    if (!parsed.ok || 'undefined' === typeof parsed.envelope) {
      Toast.show({ message: backupErrorText(parsed.code), duration: 3000 });

      return;
    }

    const envelope: IEnvelope = parsed.envelope;
    const sourceLabel: ResourceStr = envelope.meta.source === 'huawei' ?
      $r('app.string.backup_source_huawei') : $r('app.string.backup_source_wechat');

    this.importText = text;
    this.plan = undefined;
    this.importReady = true;
    this.planReady = false;
    this.planAccepted = 0;
    this.planDuplicates = 0;
    this.planInvalid = 0;
    this.summary = '';
    this.importMeta = `来自${sourceLabel}，含 ${envelope.meta.count} 条，导出于 ${envelope.meta.createdAt}`;

    hilog.info(LogDomain.PAGES, AppPagesName.MIGRATE, 'backup_parse: channel=%{public}s, count=%{public}d',
      source, envelope.meta.count);
  }

  private async pasteFromClipboard(result: PasteButtonOnClickResult): Promise<void> {
    if (PasteButtonOnClickResult.SUCCESS !== result) {
      Toast.show({ message: $r('app.string.backup_paste_denied'), duration: 3000 });

      return;
    }

    const text: string | undefined = await Clipboard.read();

    if ('undefined' === typeof text) {
      Toast.show({ message: $r('app.string.backup_import_clipboard_empty'), duration: 3000 });

      return;
    }

    this.acceptImportText(text, 'clipboard');
  }

  private async pickBackupFile(): Promise<void> {
    const context = this.getUIContext().getHostContext();

    if ('undefined' === typeof context) {
      return;
    }

    const text: string | undefined = await FileTransfer.pickText(context);

    if ('undefined' === typeof text) {
      Toast.show({ message: $r('app.string.backup_import_file_empty'), duration: 3000 });

      return;
    }

    this.acceptImportText(text, 'file');
  }

  // 导入第二步：解密 + 计划（预览 accepted / duplicates / invalid）
  private async analyzeImport(): Promise<void> {
    if (this.busy || this.importText.length === 0) {
      return;
    }

    if (this.importPassword.length === 0) {
      Toast.show({ message: $r('app.string.backup_import_password_required'), duration: 3000 });

      return;
    }

    this.busy = true;

    try {
      const plan: ImportPlan = await Dialog.execute(
        () => this.loadingDialog(),
        async (): Promise<ImportPlan> => {
          const existing: IItem[] = await Totp.all();

          return Importer.analyze(this.importText, this.importPassword, existing);
        }
      );

      this.plan = plan;
      this.planAccepted = plan.accepted.length;
      this.planDuplicates = plan.duplicates;
      this.planInvalid = plan.invalid.length;
      this.planReady = true;

      hilog.info(LogDomain.PAGES, AppPagesName.MIGRATE,
        'backup_parse: accepted=%{public}d, duplicates=%{public}d, invalid=%{public}d',
        plan.accepted.length, plan.duplicates, plan.invalid.length);
    } catch (e) {
      this.showError(e as Object);
    } finally {
      this.busy = false;
    }
  }

  // 导入第三步：串行 create + 校正，可取消；失败不中断
  private async startImport(): Promise<void> {
    if (this.busy || 'undefined' === typeof this.plan) {
      return;
    }

    const plan: ImportPlan = this.plan;

    if (plan.accepted.length === 0) {
      Toast.show({ message: $r('app.string.backup_no_plan'), duration: 3000 });

      return;
    }

    this.busy = true;
    this.cancelRequested = false;
    this.progressVisible = true;
    this.progressDone = 0;
    this.progressTotal = plan.accepted.length;
    this.progressText = `正在导入 0/${plan.accepted.length}`;
    this.summary = '';

    try {
      const report: ImportReport = await Importer.run(plan, this.itemsRuntime,
        (done: number, total: number): void => {
          this.progressDone = done;
          this.progressText = `正在导入 ${done}/${total}`;
        },
        (): boolean => this.cancelRequested);

      const parts: string[] = [];
      parts.push(`成功 ${report.done} 条`);

      if (report.failed.length > 0) {
        parts.push(`失败 ${report.failed.length} 条`);
      }

      if (report.canceled) {
        parts.push(`未执行 ${report.notExecuted} 条`);
      }

      this.summary = parts.join('，');
      this.itemsCount = this.itemsRuntime.ids.length;

      hilog.info(LogDomain.PAGES, AppPagesName.MIGRATE,
        'backup_import: done=%{public}d, failed=%{public}d, canceled=%{public}s',
        report.done, report.failed.length, report.canceled.toString());

      Toast.show({ message: this.summary, duration: 3000 });
    } catch (e) {
      this.showError(e as Object);
    } finally {
      this.busy = false;
      this.progressVisible = false;
      this.planReady = false;
      this.importReady = false;
      this.importPassword = '';
      this.plan = undefined;
      this.importText = '';
    }
  }
}
