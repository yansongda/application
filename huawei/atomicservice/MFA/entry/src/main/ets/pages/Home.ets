import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { Authorization, State } from '../models/Auth';
import { AppPagesName, LogDomain } from '../App';
import { redirectLoginPage } from '../utils/Nav';

@Entry
@ComponentV2
struct Home {
  @Local
  private authorization: Authorization =
    PersistenceV2.globalConnect({ type: Authorization, defaultCreator: () => new Authorization() })!;
  private pages: NavPathStack = AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;

  onPageShow(): void {
    hilog.info(LogDomain.PAGES, AppPagesName.HOME, '页面显示');

    if (State.NORMAL !== this.authorization.state()) {
      redirectLoginPage();
    }
  }

  build() {
    Column() {
      Navigation(this.pages, { name: 'index' })
        .titleMode(NavigationTitleMode.Mini)
        .mode(NavigationMode.Stack)
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}