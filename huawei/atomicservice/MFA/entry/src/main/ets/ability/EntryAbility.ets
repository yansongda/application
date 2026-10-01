import { UIAbility } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageV2, PersistenceV2, ThemeControl, UIContext, window } from '@kit.ArkUI';
import { Authorization } from '../models/Auth';
import { LogDomain } from '../App';
import { User } from '../models/User';
import { ItemsRuntime } from '../models/Runtime';
import { MainTheme } from '../themes/Main';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Home', (err) => {
      if (err.code) {
        // 理论上来说，这里不会出现
        hilog.error(LogDomain.ABILITY, 'ability/EntryAbility', '加载页面失败. Cause: %{public}s', JSON.stringify(err));

        return;
      }

      PersistenceV2.globalConnect({ type: Authorization, defaultCreator: () => new Authorization() });
      PersistenceV2.globalConnect({ type: User, defaultCreator: () => new User() })

      try {
        AppStorageV2.connect(UIContext, () => windowStage.getMainWindowSync().getUIContext());
        AppStorageV2.connect(NavPathStack, () => new NavPathStack());
      } catch (error) {
        hilog.error(LogDomain.ABILITY, 'ability/EntryAbility', '存储基础应用运行数据失败. Cause: %{public}s',
          JSON.stringify(error));
      }

      ThemeControl.setDefaultTheme(MainTheme.create());
    });
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
    // 恢复退后台时暂停的验证码刷新定时器（不会额外发起网络请求，数据由页面刷新时统一拉取）
    AppStorageV2.connect(ItemsRuntime, () => new ItemsRuntime())!.resumeAll();
  }

  onBackground(): void {
    // 退后台暂停所有验证码刷新定时器，避免后台空转与无效网络请求
    AppStorageV2.connect(ItemsRuntime, () => new ItemsRuntime())!.stopAll();
  }
}
