import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageV2, PersistenceV2, ThemeControl, UIContext, window } from '@kit.ArkUI';
import { Authorization } from '../models/Auth';
import { LogDomain } from '../App';
import { User } from '../models/User';
import { ItemsRuntime } from '../models/totp/ItemsRuntime';
import { FormIntent } from '../models/form/FormIntent';
import { MainTheme } from '../themes/Main';
import { Security, AppLock } from '../models/Security';
import { Privacy } from '../utils/Privacy';

export default class EntryAbility extends UIAbility {
  // 冷启动：卡片点击拉起时 want 可能携带快捷意图，写入共享状态供 Index 页消费
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleFormIntent(want);
  }

  // 热启动：元服务已在后台时点卡，不重建 Ability，新 want 直接到达
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleFormIntent(want);
  }

  private handleFormIntent(want: Want): void {
    const route: string | undefined = FormIntent.fromWant(want);

    if ('undefined' === typeof route) {
      return;
    }

    const shared: FormIntent = AppStorageV2.connect(FormIntent, () => new FormIntent())!;

    shared.route = route;
    shared.version++;

    hilog.info(LogDomain.ABILITY, 'ability/EntryAbility', '卡片意图到达: route=%{public}s', route);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Home', (err) => {
      if (err.code) {
        // 加载失败属异常路径，理论上不会出现
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

      const context = this.context;
      const security = Security.shared();

      security.load(context);
      Privacy.attach(windowStage);
      // 冷启动立即断言一次：不等 onForeground，把「窗口已可见但隐私模式尚未生效」的竞态窗口压到零；
      // onForeground 会再断言一次（代价是一次冗余系统调用，换取生命周期顺序异常时防截屏仍生效）
      Privacy.apply(security.screenProtect, 'cold_start');
      AppLock.shared().reset(security.appLock);
    });
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
    // 恢复退后台时暂停的验证码刷新定时器（端内算码为主，secret 缺失/算码失败时回退服务端；列表数据由页面刷新统一拉取）
    AppStorageV2.connect(ItemsRuntime, () => new ItemsRuntime())!.resumeAll();

    const security = Security.shared();

    Privacy.apply(security.screenProtect, 'foreground');
    AppLock.shared().onForeground();
  }

  onBackground(): void {
    // 退后台暂停所有验证码刷新定时器，避免后台空转与无效网络请求
    AppStorageV2.connect(ItemsRuntime, () => new ItemsRuntime())!.stopAll();

    const security = Security.shared();

    AppLock.shared().onBackground();

    if (security.appLock) {
      Privacy.apply(true, 'background');
    }
  }
}
