// 防截屏（窗口隐私模式）的**唯一功能入口**，一个文件回答三个问题：
// ① 用户设置要不要防截屏（enabled，持久化）② 此刻要不要遮挡（enabled || occluded）③ 怎么落地到窗口。
// 落地的系统写入细节在 utils/PrivacyWindow.ets，本文件以 PrivacyWindowWriter 别名引入——
// 同名类在两层各一个是有意的（models 管「要不要」、utils 管「怎么写」），项目内已有先例：
// models/User 与 api/User 就是用 `User as UserApi` 别名区分的。
// 名称与系统 API `Window.setWindowPrivacyMode`（隐私窗口）对齐，避免被误读为「隐私政策/隐私数据」。
import { Context } from '@kit.AbilityKit';
import { AppStorageV2, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../../App';
import { PrivacyWindow as PrivacyWindowWriter } from '../../utils/PrivacyWindow';
import { KEY_SECURITY_PRIVACY_WINDOW, Prefs } from '../../utils/Prefs';

// 用户设置默认开 = fail-closed（用户在不知情时被截屏的风险 > 自己被挡的风险）
const DEFAULT_PRIVACY_WINDOW: boolean = true;

@ObservedV2
export class PrivacyWindow {
  // 用户设置（持久化：单库 `mfa` 的 key `security.privacyWindow`，经 utils/Prefs.ets 读写）
  @Trace
  private _enabled: boolean = DEFAULT_PRIVACY_WINDOW;

  // 退后台的临时遮挡（**不持久化**）：由应用锁驱动，遮住多任务卡片快照里的验证码明文
  private _occluded: boolean = false;

  public get enabled(): boolean {
    return this._enabled;
  }

  static instance(): PrivacyWindow {
    return AppStorageV2.connect(PrivacyWindow, () => new PrivacyWindow())!;
  }

  // 缓存 windowStage（转发给 utils 层的 writer）；只由 EntryAbility.onWindowStageCreate 调用一次
  static attach(stage: window.WindowStage): void {
    PrivacyWindowWriter.attach(stage);
  }

  // 冷启动读设置（由 EntryAbility.onCreate 调用一次）
  load(context: Context): void {
    this._enabled = Prefs.getBoolean(Prefs.open(context), KEY_SECURITY_PRIVACY_WINDOW, DEFAULT_PRIVACY_WINDOW);
    hilog.info(LogDomain.MODELS, 'models/security', 'screen_protect_load: enabled=%{public}s',
      this._enabled.toString());
  }

  // 设置该项：**先落盘、成功才改内存**——失败直接 false 且内存不变（调用方提示用户），
  // 因此不需要「先乐观改内存再回滚」那套闭包。成功后立即落地到窗口，页面无需再手工 apply。
  setEnabled(context: Context, on: boolean): boolean {
    if (!Prefs.putBoolean(Prefs.open(context), KEY_SECURITY_PRIVACY_WINDOW, on)) {
      hilog.error(LogDomain.MODELS, 'models/security', 'screen_protect_save_failed: enabled=%{public}s',
        on.toString());

      return false;
    }

    this._enabled = on;
    this.apply('setting');
    hilog.info(LogDomain.MODELS, 'models/security', 'screen_protect_set: enabled=%{public}s', on.toString());

    return true;
  }

  // 把「当前该不该遮挡」写进窗口：用户设置与临时遮挡取或，是窗口状态的**唯一真相源**
  apply(cause: string): void {
    PrivacyWindowWriter.apply(this._enabled || this._occluded, cause);
  }

  // 临时遮挡开关（退后台 true / 回前台 false）；不落盘，进程结束即归零。
  // 跨功能策略（「应用锁开启时才需要遮挡快照」）留在 EntryAbility，两个模型互不依赖
  occlude(on: boolean, cause: string): void {
    this._occluded = on;
    this.apply(cause);
  }
}
