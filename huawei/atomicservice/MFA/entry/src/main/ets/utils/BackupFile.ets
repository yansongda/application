// 备份文件通道（华为侧唯一 picker + fileIo 入口）：
// - 导出：DocumentViewPicker.save 写到用户选定位置（不写应用沙箱）
// - 导入：DocumentViewPicker.select（不设后缀过滤，按内容识别）
// 日志只记事件，不打印文件内容（备份里是密文，但仍不应进日志）。
import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';
import { BACKUP_MAX_ENVELOPE_TEXT_CHARS } from '../types/Backup';

export enum FileSaveOutcome {
  SAVED,
  CANCELED,
  FAILED,
}

export enum FilePickOutcome {
  OK,
  CANCELED,
  FAILED,
  TOO_LARGE,
}

export interface FilePickResult {
  outcome: FilePickOutcome;
  text?: string;
}

const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;

/** 推荐命名 mfa-backup-YYYYMMDD-HHmm.mfa（内容为后端信封 JSON）。 */
export const buildBackupFileName = (now: Date = new Date()): string => {
  const date: string = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}`;
  const time: string = `${pad(now.getHours())}${pad(now.getMinutes())}`;

  return `mfa-backup-${date}-${time}.mfa`;
};

export class BackupFile {
  static async saveText(context: common.Context, text: string, fileName: string): Promise<FileSaveOutcome> {
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];
      options.fileSuffixChoices = ['MFA 备份|.mfa'];

      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.save(options);

      if (0 === uris.length) {
        return FileSaveOutcome.CANCELED;
      }

      const file: fileIo.File = fileIo.openSync(uris[0],
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);

      try {
        fileIo.writeSync(file.fd, text);
      } finally {
        fileIo.closeSync(file);
      }

      return FileSaveOutcome.SAVED;
    } catch (e) {
      hilog.warn(LogDomain.UTILS, 'utils/backup_file', '保存备份文件失败: %{public}s', JSON.stringify(e));

      return FileSaveOutcome.FAILED;
    }
  }

  static async pickText(context: common.Context): Promise<FilePickResult> {
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.select(options);

      if (0 === uris.length) {
        return { outcome: FilePickOutcome.CANCELED };
      }

      const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);

      try {
        const stat: fileIo.Stat = fileIo.statSync(file.fd);

        // 先按字节数拦截：UTF-8 下字符数 ≤ 字节数，超限文件不必读进内存
        if (stat.size > BACKUP_MAX_ENVELOPE_TEXT_CHARS) {
          return { outcome: FilePickOutcome.TOO_LARGE };
        }

        const buffer: ArrayBuffer = new ArrayBuffer(stat.size);

        fileIo.readSync(file.fd, buffer);

        return { outcome: FilePickOutcome.OK, text: new util.TextDecoder().decodeToString(new Uint8Array(buffer)) };
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      hilog.warn(LogDomain.UTILS, 'utils/backup_file', '读取备份文件失败: %{public}s', JSON.stringify(e));

      return { outcome: FilePickOutcome.FAILED };
    }
  }
}
