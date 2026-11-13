// 导入 / 导出加密备份（路由 user/backup）：加解密全部由服务端完成。
// - 导出：POST /api/v1/backup/export → 信封 JSON → 复制 / 保存为 .mfa 文件
// - 导入：粘贴 / 文件 / 手动文本 → 预检信封 → POST /api/v1/backup/import（批量写入，不去重）
// 口令只存在于页面内存：onHidden 立即清空，不写 preferences、不进日志。
import { AppStorageV2, LoadingDialogV2 } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPagesName, LogDomain } from '../../App';
import { Totp } from '../../api/Totp';
import { Backup as BackupApi } from '../../api/Backup';
import {
  buildExport,
  checkExportPassword,
  checkImportPassword,
  ExportResult,
  formatLocalDateTime,
  parseEnvelope
} from '../../models/Backup';
import {
  BACKUP_CLIPBOARD_MAX_CHARS,
  BackupEnvelope,
  BackupPageMode,
  BackupPageParams
} from '../../types/Backup';
import { ItemsRuntime } from '../../models/totp/ItemsRuntime';
import { FormBridge } from '../../models/form/FormBridge';
import { Clipboard } from '../../utils/Clipboard';
import { buildBackupFileName, BackupFile, FilePickOutcome, FilePickResult, FileSaveOutcome } from '../../utils/BackupFile';
import { Dialog, Toast } from '../../utils/PromptAction';
import { LoadingLease } from '../../utils/dialog/WindowCoordinator';
import { AuthExpiredError, HttpError, toError } from '../../utils/Errors';

@Builder
export function builder() {
  BackupPage()
}

@ComponentV2
struct BackupPage {
  @Local
  private mode: BackupPageMode = BackupPageMode.BOTH;
  @Local
  private itemsCount: number = 0;
  @Local
  private exportPassword: string = '';
  @Local
  private exportPasswordConfirm: string = '';
  @Local
  private exportReady: boolean = false;
  @Local
  private exportMeta: ResourceStr = '';
  @Local
  private exportClipboardAllowed: boolean = true;
  @Local
  private importReady: boolean = false;
  @Local
  private importMeta: ResourceStr = '';
  @Local
  private importPassword: string = '';
  @Local
  private manualText: string = '';
  // 导入结果摘要：`undefined` 表示不展示（成功/刷新失败两种文案都是带参数的资源，不宜用空串表达“无”）
  @Local
  private summary: ResourceStr | undefined = undefined;
  private exportText: string = '';
  private exportFileName: string = '';
  private importEnvelope: BackupEnvelope | undefined = undefined;
  private busy: boolean = false;
  private itemsRuntime: ItemsRuntime = AppStorageV2.connect(ItemsRuntime, () => new ItemsRuntime())!;

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: $r('app.integer.column_space') }) {
          if (BackupPageMode.IMPORT !== this.mode) {
            this.exportCard()
          }

          if (BackupPageMode.EXPORT !== this.mode) {
            this.importCard()
          }
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
    .onReady((context: NavDestinationContext) => {
      const params: BackupPageParams | undefined = context.pathInfo.param as BackupPageParams | undefined;

      if ('undefined' !== typeof params && null !== params && 'undefined' !== typeof params.mode) {
        this.mode = params.mode;
      }
    })
    .onShown(() => {
      this.itemsCount = this.itemsRuntime.ids.length;

      // `ItemsRuntime` 只由首页填充：从非常规入口直达本页时计数为 0，导出卡上的「当前共 N 个账号」会失真。
      // 静默拉一次自愈；失败不打扰（导出是否可行以服务端 2026/2027 为准）
      if (this.itemsCount <= 0) {
        this.reloadItems().catch(() => {
          // 失败已在本方法内记日志，这里仅避免 unhandled rejection
        });
      }
    })
    .onHidden(() => {
      this.clearSecrets();
    })
  }

  @Builder
  loadingDialog(content?: Resource) {
    LoadingDialogV2({
      content: content ?? $r('app.string.handling'),
    })
  }

  // 全局单飞 loading 的租约模型：必须 `release()` 才会真正关窗（租约带打开代号，迟到 release 不会误关下一轮）。
  // 这里把「开窗 → 执行 → 关窗」收成一处：关窗完成后再由调用方提示，避免 toast 叠在遮罩上。
  private async withLoading(content: Resource, task: () => Promise<void>): Promise<void> {
    this.busy = true;

    let lease: LoadingLease | undefined = undefined;

    try {
      lease = await Dialog.openLoading(() => this.loadingDialog(content));

      await task();
    } finally {
      if ('undefined' !== typeof lease) {
        await lease.release();
      }

      this.busy = false;
    }
  }

  // --- 导出 ---

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
        text: this.exportPassword,
      })
        .type(InputType.Password)
        .maxLength(128)
        .height(44)
        .backgroundColor($r('sys.color.background_primary'))
        .borderRadius($r('app.integer.card_radius'))
        .onChange((value: string): void => {
          this.exportPassword = value;
        })

      TextInput({
        placeholder: $r('app.string.backup_export_password_confirm_placeholder'),
        text: this.exportPasswordConfirm,
      })
        .type(InputType.Password)
        .maxLength(128)
        .height(44)
        .backgroundColor($r('sys.color.background_primary'))
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
          this.requestExport().catch(() => {
            // 失败已在 requestExport 内部提示，仅避免 unhandled rejection
          });
        })

      if (this.exportReady) {
        Button($r('app.string.backup_export_save'))
          .width('100%')
          .type(ButtonType.Capsule)
          .backgroundColor($r('sys.color.background_primary'))
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => {
            this.saveExportFile().catch(() => {
              // 失败已在 saveExportFile 内部提示，仅避免 unhandled rejection
            });
          })

        Button($r('app.string.backup_export_copy'))
          .width('100%')
          .type(ButtonType.Capsule)
          .backgroundColor($r('sys.color.background_primary'))
          .fontColor($r('sys.color.font_secondary'))
          .enabled(this.exportClipboardAllowed)
          .onClick(() => {
            this.copyExport().catch(() => {
              // 失败已在 copyExport 内部提示，仅避免 unhandled rejection
            });
          })

        Text(this.exportMeta)
          .width('100%')
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('sys.color.font_secondary'))
          .textAlign(TextAlign.Start)

        if (!this.exportClipboardAllowed) {
          Text($r('app.string.backup_export_clipboard_too_large'))
            .width('100%')
            .fontSize($r('app.float.caption_smaller_font_size'))
            .fontColor($r('sys.color.font_secondary'))
            .textAlign(TextAlign.Start)
        }
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
    .backgroundColor($r('sys.color.background_secondary'))
    .borderRadius($r('app.integer.card_radius'))
  }

  private async requestExport(): Promise<void> {
    if (this.busy) {
      return;
    }

    // 条目数与上限一律以服务端为准（2026 空 / 2027 超限，文案已映射）：
    // 本地 `ItemsRuntime` 只由首页填充，未初始化时计数为 0，用它提前拦会把「服务端明明有数据」误判成空账号
    const strength = checkExportPassword(this.exportPassword, this.exportPasswordConfirm);

    if (!strength.ok) {
      Toast.show({ message: strength.reason ?? $r('app.string.backup_failed'), duration: 3000 });

      return;
    }

    try {
      await this.withLoading($r('app.string.backup_encrypting'), async (): Promise<void> => {
        // 服务端响应也走一次预检：避免后端升级 / 代理篡改后把异常信封落成文件
        const result: ExportResult = await buildExport(BackupApi.exportBackup, this.exportPassword);

        this.exportText = result.text;
        this.exportFileName = buildBackupFileName();
        this.exportClipboardAllowed = result.text.length <= BACKUP_CLIPBOARD_MAX_CHARS;
        this.exportMeta = $r('app.string.backup_export_meta', result.count, formatLocalDateTime(result.createdAt));
        this.exportReady = true;

        // 密文已生成，口令不再需要：立即清空输入框，缩短口令在组件状态里的驻留时间
        this.exportPassword = '';
        this.exportPasswordConfirm = '';

        hilog.info(LogDomain.PAGES, AppPagesName.USER_BACKUP, 'backup_export: count=%{public}d', result.count);
      });

      Toast.show({ message: $r('app.string.backup_export_generated'), duration: 3000 });
    } catch (e) {
      this.showError(toError(e));
    }
  }

  private async saveExportFile(): Promise<void> {
    if (this.busy || this.exportText.length <= 0) {
      return;
    }

    const context = this.getUIContext().getHostContext();

    if ('undefined' === typeof context) {
      return;
    }

    this.busy = true;

    try {
      const outcome: FileSaveOutcome = await BackupFile.saveText(context, this.exportText, this.exportFileName);

      if (FileSaveOutcome.SAVED === outcome) {
        Toast.show({ message: $r('app.string.backup_saved'), duration: 3000 });
      }

      if (FileSaveOutcome.FAILED === outcome) {
        Toast.show({ message: $r('app.string.backup_save_failed'), duration: 3000 });
      }
    } catch (e) {
      this.showError(toError(e));
    } finally {
      this.busy = false;
    }
  }

  private async copyExport(): Promise<void> {
    if (this.busy || this.exportText.length <= 0) {
      return;
    }

    try {
      await Clipboard.copy(this.exportText);

      hilog.info(LogDomain.PAGES, AppPagesName.USER_BACKUP, 'backup_export: channel=clipboard');

      Toast.show({ message: $r('app.string.backup_copied'), duration: 3000 });
    } catch (e) {
      this.showError(toError(e));
    }
  }

  // --- 导入 ---

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

      // 安全控件：授权成功后本次读取剪贴板才被系统允许（普通 getData 需要受限权限，本工程不申请）
      PasteButton()
        .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
          this.pasteFromClipboard(result).catch(() => {
            // 失败已在 pasteFromClipboard 内部提示，仅避免 unhandled rejection
          });
        })

      Button($r('app.string.backup_import_file'))
        .width('100%')
        .type(ButtonType.Capsule)
        .backgroundColor($r('sys.color.background_primary'))
        .fontColor($r('sys.color.font_secondary'))
        .onClick(() => {
          this.pickBackupFile().catch(() => {
            // 失败已在 pickBackupFile 内部提示，仅避免 unhandled rejection
          });
        })

      // 安全控件样式受限时的兜底：手动粘贴（系统粘贴是用户手势，不需要应用申请权限）
      TextArea({
        placeholder: $r('app.string.backup_import_manual_placeholder'),
        text: this.manualText,
      })
        .height(96)
        .backgroundColor($r('sys.color.background_primary'))
        .borderRadius($r('app.integer.card_radius'))
        .fontSize($r('app.float.caption_smaller_font_size'))
        .onChange((value: string): void => {
          this.manualText = value;
        })

      Button($r('app.string.backup_import_manual_button'))
        .width('100%')
        .type(ButtonType.Capsule)
        .backgroundColor($r('sys.color.background_primary'))
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
          text: this.importPassword,
        })
          .type(InputType.Password)
          .maxLength(128)
          .height(44)
          .backgroundColor($r('sys.color.background_primary'))
          .borderRadius($r('app.integer.card_radius'))
          .onChange((value: string): void => {
            this.importPassword = value;
          })

        Button($r('app.string.backup_import_start'))
          .width('100%')
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('sys.color.font_on_primary'))
          .onClick(() => {
            this.startImport().catch(() => {
              // 失败已在 startImport 内部提示，仅避免 unhandled rejection
            });
          })
      }

      if ('undefined' !== typeof this.summary) {
        Text(this.summary)
          .width('100%')
          .fontSize($r('app.float.caption_font_size'))
          .textAlign(TextAlign.Start)
      }

      Text($r('app.string.backup_import_note'))
        .width('100%')
        .fontSize($r('app.float.caption_smaller_font_size'))
        .fontColor($r('sys.color.font_tertiary'))
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding($r('app.integer.page_padding'))
    .backgroundColor($r('sys.color.background_secondary'))
    .borderRadius($r('app.integer.card_radius'))
  }

  private acceptImportText(text: string, channel: string): void {
    if (text.trim().length <= 0) {
      Toast.show({ message: $r('app.string.backup_import_empty'), duration: 3000 });

      return;
    }

    try {
      // 第一步只做结构预检（不索要口令）
      const envelope: BackupEnvelope = parseEnvelope(text);

      this.importEnvelope = envelope;
      this.importReady = true;
      this.importPassword = '';
      this.summary = undefined;
      this.importMeta = $r('app.string.backup_import_meta', envelope.meta.count,
        formatLocalDateTime(envelope.meta.created_at));

      hilog.info(LogDomain.PAGES, AppPagesName.USER_BACKUP, 'backup_parse: channel=%{public}s, count=%{public}d',
        channel, envelope.meta.count);
    } catch (e) {
      this.showError(toError(e));
    }
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

    const result: FilePickResult = await BackupFile.pickText(context);

    if (FilePickOutcome.CANCELED === result.outcome) {
      return;
    }

    if (FilePickOutcome.TOO_LARGE === result.outcome) {
      Toast.show({ message: $r('app.string.backup_import_file_too_large'), duration: 3000 });

      return;
    }

    if (FilePickOutcome.FAILED === result.outcome || 'undefined' === typeof result.text) {
      Toast.show({ message: $r('app.string.backup_import_file_failed'), duration: 3000 });

      return;
    }

    this.acceptImportText(result.text, 'file');
  }

  // 第二步：一次请求交给服务端解密并批量写入；不去重、非事务（9903 时提示核对已写入条目）
  private async startImport(): Promise<void> {
    const envelope: BackupEnvelope | undefined = this.importEnvelope;

    if ('undefined' === typeof envelope || this.busy) {
      return;
    }

    const strength = checkImportPassword(this.importPassword);

    if (!strength.ok) {
      Toast.show({ message: strength.reason ?? $r('app.string.backup_failed'), duration: 3000 });

      return;
    }

    try {
      await this.withLoading($r('app.string.backup_importing'), async (): Promise<void> => {
        let imported: number = 0;

        try {
          imported = await BackupApi.importBackup(envelope, this.importPassword);
        } catch (e) {
          // 9903：部分条目已写入；仍要刷新列表，避免页面与服务端不一致
          if (e instanceof HttpError && 9903 === e.code) {
            await this.reloadItems();
          }

          throw toError(e);
        }

        // 服务端为准刷新本地列表与卡片；刷新失败不能静默——否则「成功导入 N 条」与列表不一致
        const refreshed: boolean = await this.reloadItems();

        this.summary = refreshed
          ? $r('app.string.backup_imported', imported)
          : $r('app.string.backup_imported_refresh_failed', imported);
        this.importReady = false;
        this.importMeta = '';
        this.importPassword = '';
        this.importEnvelope = undefined;
        this.manualText = '';

        hilog.info(LogDomain.PAGES, AppPagesName.USER_BACKUP, 'backup_import: imported=%{public}d', imported);
      });

      const summary: ResourceStr | undefined = this.summary;

      if ('undefined' !== typeof summary) {
        Toast.show({ message: summary, duration: 3000 });
      }
    } catch (e) {
      this.showError(toError(e));
    }
  }

  // 返回是否刷新成功：导入成功但刷新失败时调用方要据此提示用户下拉刷新
  private async reloadItems(): Promise<boolean> {
    try {
      const items = await Totp.all();

      this.itemsRuntime.reload(items.values());
      this.itemsCount = this.itemsRuntime.ids.length;

      const context = this.getUIContext().getHostContext();

      if ('undefined' !== typeof context) {
        FormBridge.sync(context, this.itemsRuntime.ids);
      }

      return true;
    } catch (e) {
      hilog.warn(LogDomain.PAGES, AppPagesName.USER_BACKUP, '导入后刷新列表失败: %{public}s', JSON.stringify(e));

      return false;
    }
  }

  private clearSecrets(): void {
    this.exportPassword = '';
    this.exportPasswordConfirm = '';
    this.exportReady = false;
    this.exportMeta = '';
    this.exportClipboardAllowed = true;
    this.exportText = '';
    this.importReady = false;
    this.importMeta = '';
    this.importPassword = '';
    this.importEnvelope = undefined;
    this.manualText = '';
    this.summary = undefined;
  }

  private showError(caught: Error): void {
    if (caught instanceof AuthExpiredError) {
      hilog.warn(LogDomain.PAGES, AppPagesName.USER_BACKUP, '备份请求认证失效，交由登录页处理');

      return;
    }

    if (caught.message.length > 0) {
      Toast.show({ message: caught.message, duration: 3000 });

      return;
    }

    Toast.show({ message: $r('app.string.backup_failed'), duration: 3000 });
  }
}
