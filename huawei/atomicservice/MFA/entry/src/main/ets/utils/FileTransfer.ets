// 备份文件通道（华为侧唯一 picker + fileIo 入口）：
// - 导出：DocumentViewPicker.save 写用户选定位置（不写应用沙箱）
// - 导入：DocumentViewPicker.select（不设后缀过滤，内容嗅探）
// 日志只记事件，不打印文件内容。
import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';

export enum FileSaveOutcome {
  SAVED = 'saved',
  CANCELED = 'canceled',
  FAILED = 'failed'
}

export class FileTransfer {
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

      const uri: string = uris[0];
      const file: fileIo.File = fileIo.openSync(uri,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);

      try {
        fileIo.writeSync(file.fd, text);
      } finally {
        fileIo.closeSync(file);
      }

      return FileSaveOutcome.SAVED;
    } catch (e) {
      hilog.warn(LogDomain.UTILS, 'utils/file_transfer', '保存备份文件失败: %{public}s', JSON.stringify(e));

      return FileSaveOutcome.FAILED;
    }
  }

  static async pickText(context: common.Context): Promise<string | undefined> {
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.select(options);

      if (0 === uris.length) {
        return undefined;
      }

      const uri: string = uris[0];
      const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);

      let content: string;

      try {
        const stat: fileIo.Stat = fileIo.statSync(file.fd);
        const buffer: ArrayBuffer = new ArrayBuffer(stat.size);

        fileIo.readSync(file.fd, buffer);
        content = new util.TextDecoder().decodeToString(new Uint8Array(buffer));
      } finally {
        fileIo.closeSync(file);
      }

      return content;
    } catch (e) {
      hilog.warn(LogDomain.UTILS, 'utils/file_transfer', '读取备份文件失败: %{public}s', JSON.stringify(e));

      return undefined;
    }
  }
}
