import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageV2, PersistenceV2, ThemeControl, UIContext, window } from '@kit.ArkUI';
import { Authorization } from '../models/Auth';
import { LogDomain } from '../App';
import { User } from '../models/User';
import { ItemsRuntime } from '../models/Runtime';
import { MainTheme } from '../themes/Main';
import { CardAction } from '../models/CardAction';

export default class EntryAbility extends UIAbility {
  // 冷启动：卡片点击拉起时 want 携带卡片动作参数，写入共享状态供 Index 页消费
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleCardAction(want);
  }

  // 热启动：元服务已在后台时点卡，不重建 Ability，新 want 直接到达
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleCardAction(want);
  }

  private handleCardAction(want: Want): void {
    const cardAction: CardAction | undefined = CardAction.fromWant(want);

    if ('undefined' === typeof cardAction) {
      return;
    }

    const shared: CardAction = AppStorageV2.connect(CardAction, () => new CardAction())!;

    shared.action = cardAction.action;
    shared.itemId = cardAction.itemId;
    shared.version++;

    hilog.info(LogDomain.ABILITY, 'ability/EntryAbility', '卡片动作到达: action=%{public}s, itemId=%{public}s',
      shared.action ?? 'undefined', shared.itemId ?? 'undefined');
  }

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
