// 剪贴板封装：把文本写入系统剪贴板。复制失败抛 Error('复制失败')，由调用方负责提示。
// 日志不打印文本内容，避免验证码进入日志。
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
}
