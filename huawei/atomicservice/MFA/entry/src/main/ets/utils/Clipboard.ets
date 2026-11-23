// 剪贴板封装：写入（复制）与读取（仅备份导入，且必须由 PasteButton 授权成功后调用）。
// 读剪贴板需要受限权限 READ_PASTEBOARD（ACL + 审核），本工程不申请该权限，只走安全控件临时授权。
// 日志不打印文本内容，避免验证码 / 备份密文进入日志。
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';

export class Clipboard {
  static async copy(text: string): Promise<void> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/clipboard', '写入剪贴板失败: %{public}s', JSON.stringify(e));

      throw new Error('复制失败');
    }
  }

  // 调用前置条件：PasteButton.onClick 返回 SUCCESS（系统已授予本次剪贴板读取权限）
  static async read(): Promise<string | undefined> {
    try {
      const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = await systemPasteboard.getData();

      // 无纯文本时 getPrimaryText() 抛错，由下方 catch 归一为 undefined
      const text: string = data.getPrimaryText();

      return text.length > 0 ? text : undefined;
    } catch (e) {
      hilog.warn(LogDomain.UTILS, 'utils/clipboard', '读取剪贴板失败: %{public}s', JSON.stringify(e));

      return undefined;
    }
  }
}
