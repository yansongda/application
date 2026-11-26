import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageV2, PersistenceV2, ThemeControl, UIContext, window } from '@kit.ArkUI';
import { Authorization } from '../models/Auth';
import { LogDomain } from '../App';
import { User } from '../models/User';
import { ItemsRuntime } from '../models/totp/ItemsRuntime';
import { Clock } from '../models/totp/Clock';
import { FormIntent } from '../models/form/FormIntent';
import { FormRoute } from '../models/form/FormRoute';
import { MainTheme } from '../themes/Main';
import { AppLock } from '../models/security/AppLock';
import { PrivacyWindow } from '../models/security/PrivacyWindow';
import { SecuritySync } from '../models/security/Sync';
import { configureHttp } from '../utils/Http';
import { SessionGuard } from '../utils/SessionGuard';
import { State } from '../types/Session';

export default class EntryAbility extends UIAbility {
  // 秒级时钟接线只做一次（进程级）：避免 onForeground / onWindowStageCreate 重复订阅
  private _clockWired: boolean = false;

  // 冷启动：卡片点击拉起时 want 可能携带快捷意图，写入共享状态供 Index 页消费
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleFormIntent(want);
    this.wireClock();

    // 网络层只负责发现认证失效并通过回调通知；token 也从这里注入，Http 不再 import 模型/UI
    configureHttp({
      token: (): string | undefined => {
        const authorization: Authorization =
          PersistenceV2.globalConnect({ type: Authorization, defaultCreator: () => new Authorization() })!;

        return authorization.accessToken;
      },
      authExpired: (state: State): void => {
        SessionGuard.onAuthExpired(state);
      },
    });
  }

  // 热启动：元服务已在后台时点卡，不重建 Ability，新 want 直接到达
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleFormIntent(want);
  }

  private handleFormIntent(want: Want): void {
    const route: FormRoute | undefined = FormIntent.fromWant(want);

    if ('undefined' === typeof route) {
      return;
    }

    const shared: FormIntent = AppStorageV2.connect(FormIntent, () => new FormIntent())!;

    shared.route = route;
    shared.createdAt = Date.now();
    shared.version++;

    hilog.info(LogDomain.ABILITY, 'ability/EntryAbility', '卡片意图到达: route=%{public}s', route);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 安全设置在这里**同步**读入（早于 onForeground，也早于页面加载）：onForeground 可能早于 loadContent
    // 的回调执行，若此时读到默认值（防截屏 = true）就会覆盖用户「已关闭」的设置，而 load 之后不再重断言
    const context = this.context;

    PrivacyWindow.instance().load(context);
    AppLock.instance().load(context);

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

      PrivacyWindow.attach(windowStage);
      // 冷启动立即断言一次：不等 onForeground，把「窗口已可见但隐私模式尚未生效」的竞态窗口压到零；
      // onForeground 会再断言一次（代价是一次冗余系统调用，换取生命周期顺序异常时防截屏仍生效）
      PrivacyWindow.instance().apply('cold_start');
      AppLock.instance().reset();
      // 冷启动也起表：onForeground 可能早于本回调，两处都调（attach 幂等，且会立即推进一次 nowMs）
      Clock.instance().attach();
    });
  }

  // 秒级时钟接线（全应用唯一）：全局 1 个 ticker 每秒推进 `nowMs`，并驱动 `ItemsRuntime#onTick`
  // 重算到期验证码。起停只由前后台回调驱动，页面切换不参与计时。
  private wireClock(): void {
    if (this._clockWired) {
      return;
    }

    this._clockWired = true;

    const runtime: ItemsRuntime = AppStorageV2.connect(ItemsRuntime, () => new ItemsRuntime())!;

    Clock.instance().subscribe((nowMs: number): void => runtime.onTick(nowMs));
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
    // 回前台：立即推进一次 nowMs（不等下一个整秒）并恢复计时，`onTick` 会把退后台期间
    // 跨过的验证码重新算出来（端内算码为主，secret 缺失时由 ItemsRuntime 汇总一次服务端兜底）
    this.wireClock();
    Clock.instance().attach();

    // 先恢复用户设置（同时清掉退后台的临时遮挡），再按 60s 阈值判定是否重锁
    PrivacyWindow.instance().occlude(false, 'foreground');
    AppLock.instance().onForeground();

    // 上次退后台 / 上次运行时的安全设置若没同步成功（dirty），回前台顺手补一次
    SecuritySync.flush(this.context);
  }

  onBackground(): void {
    // 退后台停表：只停调度，避免后台空转（nowMs 保持最后值，回前台 attach 会立即补一次）
    Clock.instance().detach();

    AppLock.instance().onBackground();

    // 应用锁开启时临时遮挡多任务卡片快照（此刻屏上是 TOTP 明文码）；防截屏已开启时该值本就为 true
    if (AppLock.instance().enabled) {
      PrivacyWindow.instance().occlude(true, 'background');
    }
  }
}
