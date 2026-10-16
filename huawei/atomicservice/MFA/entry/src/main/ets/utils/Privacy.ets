// 隐私模式（防截屏）唯一入口。
// **隐私模式只允许经本文件的 Privacy.apply 修改**：页面级直接调用 setWindowPrivacyMode
// 会与全局设置互相破坏（官方 FAQ：getLastWindow 异步延迟竞态导致隐私模式偶发失效/互相覆盖）。
// 本文件在 onWindowStageCreate 时缓存 WindowStage（规避 getLastWindow 的异步延迟），并保证两条不变量：
// ① 每次 apply 至少写入一次（生命周期节点需要重断言，不能被"值没变"吞掉）；
// ② 写入在途期间再 apply 只更新目标值，当前写入结束后补写一次 —— 快速连续切换最多 2 次系统调用，
//    且最终值一定落地（不再出现排队堆积）。
// 单次写入另加超时兜底：避免某个 Promise 永不 settle 时把后续所有切换永久堵死（防截屏会静默失效，
// 且监控看不到失败）。见技术设计 §3.2。
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';

// 单次 setWindowPrivacyMode 的超时兜底（毫秒）：超时视为未生效，结束本轮排空，下一次 apply 会重试
const WRITE_TIMEOUT_MS: number = 1000;

export class Privacy {
  private static _stage: window.WindowStage | undefined;
  // 最后一次请求的目标值（连续切换只保证最终值落地）
  private static _target: boolean | undefined;
  private static _cause: string = '';
  // 脏标记：apply 置位，drain 取走；写入期间又 apply 会在本轮结束后补写一次
  private static _dirty: boolean = false;
  private static _writing: boolean = false;

  // 缓存 windowStage；由 EntryAbility.onWindowStageCreate 调用一次
  static attach(stage: window.WindowStage): void {
    Privacy._stage = stage;
    hilog.info(LogDomain.UTILS, 'utils/privacy', 'attach');
  }

  // 唯一写入口：只记录目标值；写入在途时不排队（drain 结束后会自行补写最后一次目标值）
  static apply(on: boolean, cause: string): void {
    Privacy._target = on;
    Privacy._cause = cause;
    Privacy._dirty = true;

    if (Privacy._writing) {
      return;
    }

    Privacy.drain();
  }

  private static async drain(): Promise<void> {
    Privacy._writing = true;

    try {
      while (Privacy._dirty) {
        const on: boolean | undefined = Privacy._target;
        const cause: string = Privacy._cause;

        Privacy._dirty = false;

        if ('undefined' === typeof on) {
          break;
        }

        // 失败/超时不重试：避免对同一目标值无限重试，交给下一次 apply（生命周期节点一定会来）
        if (!await Privacy.write(on, cause)) {
          break;
        }
      }
    } finally {
      Privacy._writing = false;
    }
  }

  private static async write(on: boolean, cause: string): Promise<boolean> {
    const stage: window.WindowStage | undefined = Privacy._stage;

    if ('undefined' === typeof stage) {
      // 视为已处理：stage 未挂载时不该让 drain 反复重试同一目标值
      hilog.warn(LogDomain.UTILS, 'utils/privacy', 'set_skipped: stage_not_attached');

      return true;
    }

    let timeoutId: number = -1;

    try {
      const written: Promise<boolean> = stage.getMainWindowSync().setWindowPrivacyMode(on)
        .then((): boolean => {
          hilog.info(LogDomain.UTILS, 'utils/privacy', 'set: privacyMode=%{public}s, cause=%{public}s',
            on.toString(), cause);

          return true;
        })
        .catch((e: Object): boolean => {
          hilog.error(LogDomain.UTILS, 'utils/privacy', 'set_failed: %{public}s', JSON.stringify(e));

          return false;
        });
      const timeout: Promise<boolean> = new Promise<boolean>((resolve: (value: boolean) => void): void => {
        timeoutId = setTimeout((): void => {
          hilog.error(LogDomain.UTILS, 'utils/privacy', 'set_timeout: privacyMode=%{public}s, cause=%{public}s',
            on.toString(), cause);

          resolve(false);
        }, WRITE_TIMEOUT_MS);
      });

      return await Promise.race<boolean>([written, timeout]);
    } catch (e) {
      // getMainWindowSync() / setWindowPrivacyMode() 可能**同步**抛（201 无权限 / 1300002 窗口状态异常）：
      // 必须在这里兜住——同步异常不会进入上面的 .catch，否则会穿透 drain 成为未处理的 Promise 拒绝
      hilog.error(LogDomain.UTILS, 'utils/privacy', 'set_failed: sync=true, err=%{public}s', JSON.stringify(e));

      return false;
    } finally {
      if (-1 !== timeoutId) {
        clearTimeout(timeoutId);
      }
    }
  }
}
