import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { Authorization, State } from '../models/Auth';
import { AppLock } from '../models/security/AppLock';
import { AppPagesName, LogDomain } from '../App';
import { LockScreen } from '../components/LockScreen';
import { redirectLoginPage } from '../utils/Nav';

@Entry
@ComponentV2
struct Home {
  @Local
  private authorization: Authorization =
    PersistenceV2.globalConnect({ type: Authorization, defaultCreator: () => new Authorization() })!;
  @Local
  private appLock: AppLock = AppLock.instance();
  private pages: NavPathStack = AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;

  onPageShow(): void {
    hilog.info(LogDomain.PAGES, AppPagesName.HOME, '页面显示');

    if (State.NORMAL !== this.authorization.state()) {
      redirectLoginPage();
    }
  }

  onBackPress(): boolean {
    return this.appLock.locked;
  }

  build() {
    Stack() {
      Column() {
        Navigation(this.pages, { name: 'index' })
          .titleMode(NavigationTitleMode.Mini)
          .mode(NavigationMode.Stack)
      }
      .backgroundColor($r('sys.color.background_secondary'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (this.appLock.locked) {
        LockScreen()
      }
    }
    .width('100%')
    .height('100%')
  }
}