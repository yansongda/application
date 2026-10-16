// 锁定遮罩（LockScreen）：不注册路由、由 pages/Home 在锁定态条件渲染；
// 不触碰导航栈（底层 Navigation 保持挂载），因此无法被返回键/弹栈绕过。
import { userAuth } from '@kit.UserAuthenticationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPagesName, LogDomain } from '../App';
import { AppLock, VerifyOutcome } from '../models/Security';
import { Toast } from '../utils/PromptAction';

@ComponentV2
export struct LockScreen {
  private appLock: AppLock = AppLock.shared();
  @Local
  private hint?: Resource = undefined;

  aboutToAppear(): void {
    this.trigger();
  }

  build() {
    Column({ space: $r('app.integer.column_space') }) {
      Image($r('app.media.icon')).width('30%')
      Text($r('app.string.lock_page_locked')).fontSize($r('app.float.subtitle_font_size'))
      Text($r('app.string.lock_page_hint')).fontSize($r('app.float.body_font_size')).fontColor($r('sys.color.font_secondary'))
      if (this.hint) {
        Text(this.hint).fontSize($r('app.float.caption_font_size')).fontColor($r('sys.color.warning'))
      }
      Button($r('app.string.lock_page_unlock')).width('50%').onClick(() => { this.trigger(); })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private trigger(): void {
    const context = this.getUIContext().getHostContext();

    if ('undefined' === typeof context) {
      // 拿不到 context 属异常路径：记日志便于排查「锁定后点解锁没反应」
      hilog.warn(LogDomain.PAGES, AppPagesName.HOME, 'lock_screen: context_undefined');

      return;
    }
    this.appLock.verify(context, (outcome: VerifyOutcome, code?: number): void => { this.onOutcome(outcome, code); });
  }

  private onOutcome(outcome: VerifyOutcome, code?: number): void {
    switch (outcome) {
      case VerifyOutcome.SUCCESS:
        // 验证成功：遮罩随 locked=false 自动消失，无需处理
        break;
      case VerifyOutcome.NO_CREDENTIAL:
        // 设备无凭据：AppLock 已在回调前 unlock()，遮罩将于下一帧卸载，内联 hint 用户根本看不到，
        // 必须用 Toast 提示（防锁死降级，见技术设计 §3.5）
        Toast.show({ message: $r('app.string.lock_page_no_credential'), duration: 3000 });
        break;
      case VerifyOutcome.FAILED:
        // 按原始错误码映射定向文案：禁止硬编码码值，一律用 SDK 常量比较（见技术设计 §3.5 降级表）
        if (code === userAuth.UserAuthResultCode.LOCKED) {
          this.hint = $r('app.string.lock_page_locked_out');
        } else if (code === userAuth.UserAuthResultCode.PIN_EXPIRED) {
          this.hint = $r('app.string.lock_page_pin_expired');
        } else {
          this.hint = $r('app.string.lock_page_failed');
        }
        break;
      case VerifyOutcome.CANCELED:
        this.hint = $r('app.string.lock_page_failed');
        break;
      case VerifyOutcome.SKIPPED:
        // 已在验证中 / 命中 3 秒防抖：不改 hint（避免闪烁），由用户 3 秒后手动重试
        break;
    }
  }
}
