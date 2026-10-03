import { ItemRuntime, ItemsRuntime } from '../../models/Runtime';
import { CardAction } from '../../models/card/CardAction';
import { CardSnapshotItem } from '../../utils/CardSnapshot';
import { Clipboard } from '../../utils/Clipboard';
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
import { IndexGuideState } from '../../models/Guide';
import { EmptyState } from '../../components/index/EmptyState';
import { AddFab } from '../../components/index/AddFab';
import { TotpListView } from '../../components/index/TotpListView';
import { CardBridge } from '../../models/card/CardBridge';

@Builder
export function builder() {
  Index()
}

@ComponentV2
export struct Index {
  @Local guideState: IndexGuideState =
    PersistenceV2.globalConnect({ type: IndexGuideState, defaultCreator: () => new IndexGuideState() })!;
  @Local
  private isRefreshing: boolean = false;
  @Local
  private isSortMode: boolean = false;
  // 本次进入是否展示引导页（内存态；持久化标记只记录「已不再展示」，避免写入标记后立刻把引导页隐藏）
  @Local
  private isGuideVisible: boolean = false;
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
  // 卡片动作（点卡取码）：EntryAbility 写入，@Monitor 感知；必须带 @Local 才能被 @Monitor 监听到变化
  @Local private cardAction: CardAction = AppStorageV2.connect(CardAction, () => new CardAction())!;
  // 卡片动作消费互斥：避免 @Monitor / onActive / refresh 锚点并发重复消费
  private isConsuming: boolean = false;

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Refresh({ refreshing: this.isRefreshing!! }) {
          if (this.itemsRuntime.ids.length <= 0) {
            EmptyState({
              isGuideVisible: this.isGuideVisible,
              onDismissGuide: (): void => {
                this.isGuideVisible = false;
              },
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

      // 先消费卡片动作（若已有待办且列表已就绪则立即复制），再常规刷新
      this.consumeCardAction().catch(() => {
        // 失败已内部处理，仅避免 unhandled rejection
      });

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
      this.decideGuide();
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

  // 空数据时只首次展示引导页：决定展示的同时立刻持久化标记，之后数据仍为空也只展示空状态
  private decideGuide(): void {
    if (this.itemsRuntime.ids.length > 0) {
      this.isGuideVisible = false;

      return;
    }

    if (this.isGuideVisible || this.guideState.isSkipped) {
      return;
    }

    this.isGuideVisible = true;
    this.guideState.isSkipped = true;
    PersistenceV2.save(IndexGuideState);
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
      this.decideGuide();
      this.syncCards();
    } finally {
      this.isFetching = false;

      // 待办重试锚点：refresh 被去重/未激活时，卡片待办在此补消费（isConsuming 期间会被互斥拦下）
      if ('undefined' !== typeof this.cardAction.action) {
        this.consumeCardAction().catch(() => {
          // 仅避免 unhandled rejection
        });
      }
    }
  }

  // 卡片快照同步（单入口）：账号列表变化后写 preferences 并主动推送最新数据到已添加的卡片
  private syncCards(): void {
    const context = this.getUIContext().getHostContext();

    if ('undefined' === typeof context) {
      return;
    }

    CardBridge.sync(context, this.itemsRuntime.ids.map((id: string): CardSnapshotItem => ({
      id: id,
      issuer: this.itemsRuntime.get(id).issuer,
      username: this.itemsRuntime.get(id).username,
    })));
  }

  // 卡片动作到达（EntryAbility 写入 version++ 触发）；消费失败已内部处理，这里仅避免 unhandled rejection
  @Monitor('cardAction.version')
  onCardActionChange(): void {
    this.consumeCardAction().catch(() => {
      // 仅避免 unhandled rejection
    });
  }

  // 消费卡片动作：点卡取码（复制首个/指定账号验证码到剪贴板）。互斥 + 仅成功后清空待办。
  private async consumeCardAction(): Promise<void> {
    if (this.isConsuming) {
      return;
    }

    if ('copy' !== this.cardAction.action || !(this.cardAction.version > 0)) {
      return;
    }

    this.isConsuming = true;

    try {
      // 列表未就绪时先拉取；refresh 并发时可能被 isFetching 去重而静默返回，需复查 ids
      if (this.itemsRuntime.ids.length <= 0) {
        try {
          await this.refresh();
        } catch (e) {
          hilog.warn(LogDomain.PAGES, AppPagesName.INDEX, '点卡取码前置刷新失败: %{public}s', JSON.stringify(e));

          return;
        }

        // 被去重（并发请求进行中）：本轮不消费，保留待办，由 refresh 锚点补消费
        if (this.isFetching) {
          return;
        }

        // 永挂兜底：refresh 成功但确无账号 → 清空待办，避免日后添加首个账号时意外自动复制
        if (this.itemsRuntime.ids.length <= 0) {
          this.cardAction.action = undefined;
          this.cardAction.itemId = undefined;

          return;
        }
      }

      // 定位运行时：itemId 指定且存在则用之，否则（未指定/条目已删）回退首个账号
      let targetId: string = this.itemsRuntime.ids[0];

      if ('undefined' !== typeof this.cardAction.itemId &&
        this.itemsRuntime.ids.includes(this.cardAction.itemId)) {
        targetId = this.cardAction.itemId;
      }

      try {
        await this.itemsRuntime.get(targetId).freshCode();
      } catch (e) {
        hilog.warn(LogDomain.PAGES, AppPagesName.INDEX, '点卡取码计算失败: %{public}s', JSON.stringify(e));

        return;
      }

      const code: string | undefined = this.itemsRuntime.get(targetId).code;

      if ('undefined' === typeof code || code.length <= 0) {
        return;
      }

      try {
        await Clipboard.copy(code);

        // 仅成功后清空待办
        this.cardAction.action = undefined;
        this.cardAction.itemId = undefined;

        Toast.show({ message: $r('app.string.index_index_page_copied'), duration: 3000 });
      } catch (e) {
        hilog.warn(LogDomain.PAGES, AppPagesName.INDEX, '点卡取码复制失败，保留待办: %{public}s', JSON.stringify(e));

        Toast.show({ message: $r('app.string.index_index_page_copy_failed'), duration: 3000 });
      }
    } finally {
      this.isConsuming = false;
    }
  }
}
