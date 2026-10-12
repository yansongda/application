// 隐私模式（防截屏）唯一入口。
// **隐私模式只允许经本文件的 Privacy.apply 修改**：页面级直接调用 setWindowPrivacyMode
// 会与全局设置互相破坏（官方 FAQ：getLastWindow 异步延迟竞态导致隐私模式偶发失效/互相覆盖）。
// 本文件在 onWindowStageCreate 时缓存 WindowStage（规避 getLastWindow 的异步延迟），
// 并对写入做 Promise 串联排队，保证后调用的 apply 最终生效（技术设计 §3.2）。
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';

export class Privacy {
  private static _stage: window.WindowStage | undefined;
  private static _pending: Promise<void> = Promise.resolve();

  // 缓存 windowStage；由 EntryAbility.onWindowStageCreate 调用一次
  static attach(stage: window.WindowStage): void {
    Privacy._stage = stage;
    hilog.info(LogDomain.UTILS, 'utils/privacy', 'attach');
  }

  // 唯一写入口：链式排队（Promise 串联），保证后调用者最终生效
  static apply(on: boolean, cause: string): void {
    Privacy._pending = Privacy._pending.then(() => Privacy.write(on, cause)).catch(() => {
      // 失败已在 write 内记日志，这里只保证链不中断
    });
  }

  private static async write(on: boolean, cause: string): Promise<void> {
    const stage: window.WindowStage | undefined = Privacy._stage;

    if ('undefined' === typeof stage) {
      hilog.warn(LogDomain.UTILS, 'utils/privacy', 'set_skipped: stage_not_attached');
      return;
    }

    try {
      await stage.getMainWindowSync().setWindowPrivacyMode(on);
      hilog.info(LogDomain.UTILS, 'utils/privacy', 'set: privacyMode=%{public}s, cause=%{public}s',
        on.toString(), cause);
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/privacy', 'set_failed: %{public}s', JSON.stringify(e));
    }
  }
}
