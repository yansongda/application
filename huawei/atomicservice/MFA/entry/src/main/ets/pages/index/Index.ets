import { ItemRuntime } from '../../models/totp/ItemRuntime';
import { ItemsRuntime } from '../../models/totp/ItemsRuntime';
import {
  AdvancedDialogV2Button,
  AlertDialogV2,
  AppStorageV2,
  LoadingDialogV2,
  PersistenceV2
} from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Dialog, Toast } from '../../utils/PromptAction';
import { AppPagesName, LogDomain } from '../../App';
import { SortRequestItem, Totp } from '../../api/Totp';
import { scanBarcode } from '@kit.ScanKit';
import { User } from '../../models/User';
import { displayOr } from '../../utils/Display';
import { EmptyState } from '../../components/index/EmptyState';
import { AddFab } from '../../components/index/AddFab';
import { TotpListView } from '../../components/index/TotpListView';
import { FormBridge } from '../../models/form/FormBridge';
import { FormIntent } from '../../models/form/FormIntent';

@Builder
export function builder() {
  Index()
}

@ComponentV2
export struct Index {
  @Local
  private isRefreshing: boolean = false;
  @Local
  private isSortMode: boolean = false;
  private snapshotIds: string[] = [];
  // 请求去重：避免 onActive 与下拉刷新并发发起 Totp.all()
  private isFetching: boolean = false;
  @Local
  private itemsRuntime: ItemsRuntime = AppStorageV2.connect(ItemsRuntime, () => new ItemsRuntime())!;
  @Local
  private user: User =
    PersistenceV2.globalConnect({ type: User, defaultCreator: () => new User() })!;
  private swipeActionId?: string;
  private pages: NavPathStack = AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;
  // 卡片意图（点卡快捷入口）：EntryAbility 写入，@Monitor 感知；必须带 @Local 才能被 @Monitor 监听到变化
  @Local private formIntent: FormIntent = AppStorageV2.connect(FormIntent, () => new FormIntent())!;

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Refresh({ refreshing: this.isRefreshing!! }) {
          if (this.itemsRuntime.ids.length <= 0) {
            EmptyState({
              onScan: (): void => {
                this.addByScan();
              },
              onInput: (): void => {
                this.openCreate();
              },
              onHelp: (): void => {
                this.openHelp();
              }
            })
          } else {
            TotpListView({
              itemsRuntime: this.itemsRuntime,
              isSortMode: this.isSortMode,
              onToggleSort: (): void => {
                this.toggleSort();
              },
              onDetail: (id: string): void => {
                this.openDetail(id);
              },
              onDelete: (id: string): void => {
                this.requestDelete(id);
              }
            })
          }
        }
        .onRefreshing(() => {
          if (this.isSortMode) {
            this.isRefreshing = false;

            return;
          }

          this.refresh().catch(() => {
            // 失败已由重试对话框提示，仅避免 unhandled rejection
          }).finally(() => {
            this.isRefreshing = false;
          });
        })
        .refreshOffset(64)
        .pullToRefresh(true)

        // 空态已有两个等价主入口（扫码/输入），隐藏 FAB 避免重复；排序态同样隐藏
        if (!this.isSortMode && this.itemsRuntime.ids.length > 0) {
          AddFab({
            onScan: (): void => {
              this.addByScan();
            },
            onInput: (): void => {
              this.openCreate();
            }
          })
        }
      }
    }
    .title(this.title())
    .hideBackButton(true)
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onActive(() => {
      hilog.info(LogDomain.PAGES, AppPagesName.INDEX, '页面显示');

      if (this.isSortMode) {
        return;
      }

      // 先消费卡片意图（冷启动时 want 已到达，「添加账号」需立即跳转），再常规刷新
      this.consumeFormIntent();

      this.refresh().catch(() => {
        // 失败已由重试对话框提示，仅避免 unhandled rejection
      });
    })
    .onHidden(() => {
      hilog.info(LogDomain.PAGES, AppPagesName.INDEX, '页面隐藏');

      // 仅暂停定时器，保留运行时实例以便返回时原地增量刷新
      this.itemsRuntime.stopAll();
    })
  }

  @Builder
  title() {
    Row() {
      Image(displayOr(this.user.config.avatar, $r('app.media.default_avatar')))
        .width($r('app.integer.avatar_size'))
        .height($r('app.integer.avatar_size'))
        .autoResize(true)
        .interpolation(ImageInterpolation.Medium)
        .margin({ right: 10 })
        .borderRadius($r('app.integer.card_radius'))
        .onError(() => {
          hilog.warn(LogDomain.PAGES, AppPagesName.INDEX, '头像加载失败，保持当前展示');
        })
        .onClick(() => {
          this.pages.pushPathByName(AppPagesName.USER_DETAIL, null);
        })

      Text($r("app.string.app_name_short")).fontWeight(FontWeight.Bold).fontSize($r('app.float.title_font_size'))
    }
    .width('100%')
    .height('100%')
    .margin({ left: 10, right: 10 })
    .alignItems(VerticalAlign.Center)
  }

  // 排序态切换：进入排序 / 保存排序（失败由 Toast 提示并回滚）
  private toggleSort(): void {
    if (this.isSortMode) {
      this.saveSort().catch(() => {
        // 失败已由 Toast 提示，仅避免 unhandled rejection
      });

      return;
    }

    this.enterSortMode();
  }

  // 打开验证码详情：复用列表项持有的运行时实例
  private openDetail(id: string): void {
    this.pages.pushPathByName(AppPagesName.INDEX_DETAIL, new ItemRuntime(this.itemsRuntime.get(id)));
  }

  // 请求删除：记录待删 id 并弹确认框（真正删除在 deleteDialog 内）
  private requestDelete(id: string): void {
    this.swipeActionId = id;

    Dialog.open(() => this.deleteDialog());
  }

  // 手动输入添加
  private openCreate(): void {
    this.pages.pushPathByName(AppPagesName.INDEX_CREATE, null);
  }

  // 使用帮助
  private openHelp(): void {
    this.pages.pushPathByName(AppPagesName.HELP, null);
  }

  @Builder
  loadingDialog(content?: Resource) {
    LoadingDialogV2({
      content: content ?? $r('app.string.handling'),
    })
  }

  @Builder
  addFailedDialog(content: string) {
    AlertDialogV2({
      primaryTitle: $r('app.string.index_index_page_add_failed_title'),
      content,
      primaryButton: new AdvancedDialogV2Button({
        content: $r('app.string.ok'),
        role: ButtonRole.ERROR,
      }),
    })
  }

  @Builder
  deleteDialog() {
    AlertDialogV2({
      primaryTitle: $r('app.string.index_index_page_delete_title'),
      content: $r('app.string.index_index_page_delete_content'),
      primaryButton: new AdvancedDialogV2Button({
        content: $r('app.string.index_index_page_cancel_name'),
      }),
      secondaryButton: new AdvancedDialogV2Button({
        content: $r('app.string.index_index_page_delete_name'),
        role: ButtonRole.ERROR,
        action: async () => {
          if ('undefined' == typeof this.swipeActionId) {
            return;
          }

          try {
            const dialogId = await Dialog.open(() => this.loadingDialog());

            await Totp.delete(this.swipeActionId);
            this.itemsRuntime.delete(this.swipeActionId);
            this.swipeActionId = undefined;
            this.syncCards();

            Dialog.close(dialogId);
          } catch (e) {
            await Dialog.open(() => this.deleteFailedDialog(e.message));
          }
        }
      }),
    })
  }

  @Builder
  deleteFailedDialog(content: string) {
    AlertDialogV2({
      primaryTitle: $r('app.string.index_index_page_delete_failed_title'),
      content,
      primaryButton: new AdvancedDialogV2Button({
        content: $r('app.string.ok'),
        role: ButtonRole.ERROR,
      }),
    })
  }

  @Builder
  fetchFailedDialog(action: () => void) {
    AlertDialogV2({
      primaryTitle: $r('app.string.index_index_page_fetch_failed_title'),
      content: $r('app.string.index_index_page_delete_failed_content'),
      primaryButton: new AdvancedDialogV2Button({
        content: $r('app.string.cancel'),
      }),
      secondaryButton: new AdvancedDialogV2Button({
        content: $r('app.string.retry'),
        role: ButtonRole.ERROR,
        action,
      }),
    })
  }

  private async addByScan(): Promise<void> {
    const context = this.getUIContext().getHostContext();

    if ('undefined' === typeof context) {
      return;
    }

    let uri: string;

    try {
      const result = await scanBarcode.startScanForResult(context);

      uri = result.originalValue;
    } catch (e) {
      hilog.warn(LogDomain.PAGES, AppPagesName.INDEX, '扫码取消或失败: %{public}s', JSON.stringify(e));

      return;
    }

    hilog.info(LogDomain.PAGES, AppPagesName.INDEX, '扫码结果: %{public}s', uri);

    try {
      const data =
        await Dialog.execute(() => this.loadingDialog($r('app.string.handling')),
          () => Totp.create(uri));

      this.itemsRuntime.add(data);
      this.syncCards();
    } catch (e) {
      await Dialog.open(() => this.addFailedDialog(e.message));
    }
  }

  private enterSortMode(): void {
    this.isSortMode = true;
    this.snapshotIds = [...this.itemsRuntime.ids];
  }

  private async saveSort(): Promise<void> {
    const reqItems: SortRequestItem[] = [];
    const len = this.itemsRuntime.ids.length;

    this.itemsRuntime.ids.forEach((id: string, idx: number): void => {
      reqItems.push({ id: id, sort: len - 1 - idx });
    });

    try {
      await Dialog.execute(() => this.loadingDialog(), () => Totp.sort(reqItems));

      this.isSortMode = false;
      this.syncCards();
    } catch (e) {
      hilog.warn(LogDomain.PAGES, AppPagesName.INDEX, '排序失败: %{public}s', JSON.stringify(e));

      // 服务端未变更，回滚到进入排序模式时的顺序
      this.itemsRuntime.restore(this.snapshotIds);

      Toast.show({ message: $r('app.string.index_index_page_sort_failed'), duration: 3000 });
    } finally {
      this.snapshotIds = [];
    }
  }

  private async refresh(): Promise<void> {
    if (this.isFetching) {
      return;
    }

    this.isFetching = true;

    try {
      const items =
        await Dialog.execute(() => this.loadingDialog($r('app.string.loading')), () => Totp.all(),
          () => this.fetchFailedDialog(() => this.refresh()));

      this.itemsRuntime.reload(items.values());
      this.syncCards();
    } finally {
      this.isFetching = false;
    }
  }

  // 卡片快照同步（单入口）：账号列表变化后写 preferences 并主动推送最新数据到已添加的卡片
  private syncCards(): void {
    const context = this.getUIContext().getHostContext();

    if ('undefined' === typeof context) {
      return;
    }

    FormBridge.sync(context, this.itemsRuntime.ids);
  }

  // 卡片意图到达（EntryAbility 写入 version++ 触发）
  @Monitor('formIntent.version')
  onFormIntentChange(): void {
    this.consumeFormIntent();
  }

  // 消费卡片意图：'scan' 直达扫码添加、'input' 直达手动输入添加；消费一次即清空，避免重复触发
  private consumeFormIntent(): void {
    const route: string | undefined = this.formIntent.route;

    if ('undefined' === typeof route || !(this.formIntent.version > 0)) {
      return;
    }

    this.formIntent.route = undefined;

    if ('scan' === route) {
      this.addByScan().catch(() => {
        // 取消/失败已在 addByScan 内部处理，仅避免 unhandled rejection
      });

      return;
    }

    if ('input' === route) {
      this.pages.pushPathByName(AppPagesName.INDEX_CREATE, null);
    }
  }
}
