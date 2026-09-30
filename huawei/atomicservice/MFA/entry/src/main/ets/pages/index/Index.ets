import { ItemRuntime, ItemsRuntime } from '../../models/Runtime';
import {
  AdvancedDialogV2Button,
  AlertDialogV2,
  AppStorageV2,
  LoadingDialogV2,
  PersistenceV2,
  SymbolGlyphModifier
} from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Authorization } from '../../models/Auth';
import { Dialog, Toast } from '../../utils/PromptAction';
import { AppPagesName, LogDomain } from '../../App';
import { SortRequestItem, Totp } from '../../api/Totp';
import { scanBarcode } from '@kit.ScanKit';
import { User } from '../../models/User';

const GUIDE_STEPS: number = 4;

@ObservedV2
export class IndexGuideState {
  // 引导页是否已不再展示（持久化）：点过「跳过/开始使用」，或已自动展示过一次
  @Trace isSkipped: boolean = false;
}

@Builder
export function builder() {
  Index()
}

@ComponentV2
export struct Index {
  @Local guideState: IndexGuideState = PersistenceV2.globalConnect({ type: IndexGuideState, defaultCreator: () => new IndexGuideState() })!;
  @Local
  authorization: Authorization =
    PersistenceV2.globalConnect({ type: Authorization, defaultCreator: () => new Authorization() })!;
  @Local
  private isRefreshing: boolean = false;
  @Local
  private isSortMode: boolean = false;
  // 本次进入是否展示引导页（内存态；持久化标记只记录「已不再展示」，避免写入标记后立刻把引导页隐藏）
  @Local
  private isGuideVisible: boolean = false;
  @Local
  private guideIndex: number = 0;
  private snapshotIds: string[] = [];
  private guideSwiper: SwiperController = new SwiperController();
  @Local
  private itemsRuntime: ItemsRuntime = AppStorageV2.connect(ItemsRuntime, () => new ItemsRuntime())!;
  private user: User =
    PersistenceV2.globalConnect({ type: User, defaultCreator: () => new User() })!;
  private scroller: ListScroller = new ListScroller();
  private swipeActionId?: string;
  private pages: NavPathStack = AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Refresh({ refreshing: this.isRefreshing!! }) {
          if (this.itemsRuntime.ids.length <= 0) {
            this.guide()
          } else {
            this.main()
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

        if (!this.isSortMode && !this.isGuideVisible) {
          Button({ type: ButtonType.Circle }) {
            Row() {
              Text() {
                SymbolSpan($r('sys.symbol.plus'))
                  .fontSize(35)
                  .fontColor([$r('sys.color.font_on_primary')])
              }
            }
          }
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('sys.color.font_on_primary'))
          .padding({
            top: $r('app.integer.page_padding'),
            bottom: $r('app.integer.page_padding'),
            left: $r('app.integer.page_padding'),
            right: $r('app.integer.page_padding')
          })
          .margin({ bottom: 50, right: 50 })
          .bindMenu([
            {
              value: $r('app.string.index_index_page_add_by_scan'),
              symbolIcon: new SymbolGlyphModifier($r('sys.symbol.line_viewfinder')),
              action: () => {
                this.addByScan();
              },
            },
            {
              value: $r('app.string.index_index_page_add_by_input'),
              symbolIcon: new SymbolGlyphModifier($r('sys.symbol.doc_plaintext_and_pencil')),
              action: () => {
                this.pages.pushPathByName(AppPagesName.INDEX_CREATE, null);
              },
            }
          ])
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
      Image(this.user.config.avatar ?? $r('app.media.default_avatar'))
        .width(30)
        .height(30)
        .autoResize(true)
        .interpolation(ImageInterpolation.Medium)
        .margin({ right: 10 })
        .borderRadius(10)
        .onClick(() => {
          this.pages.pushPathByName(AppPagesName.USER_DETAIL, null);
        })

      Text($r("app.string.app_name_short")).fontWeight(FontWeight.Bold).fontSize(30)
    }
    .width('100%')
    .height('100%')
    .margin({ left: 10, right: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  guide() {
    if (!this.isGuideVisible) {
      Column() {
        Text() {
          SymbolSpan($r('sys.symbol.exclamationmark_circle'))
        }
        .fontSize(50)

        Text($r('app.string.index_index_page_data_empty'))
          .margin({ top: 10 })
      }
      .margin({ top: $r('app.integer.page_margin') })
      .width('100%')
      .height('100%')
    } else {
      Column() {
        Swiper(this.guideSwiper) {
          this.guideStep($r('sys.symbol.lock_shield'), $r('app.string.index_guide_page_step_security_title'))
          this.guideActionStep($r('sys.symbol.qrcode'), $r('app.string.index_guide_page_step_scan_title'),
            $r('app.string.index_index_page_add_by_scan'), (): void => {
              this.addByScan();
            })
          this.guideActionStep($r('sys.symbol.doc_plaintext_and_pencil'),
            $r('app.string.index_guide_page_step_input_title'),
            $r('app.string.index_index_page_add_by_input'), (): void => {
              this.pages.pushPathByName(AppPagesName.INDEX_CREATE, null);
            })
          this.guideStep($r('sys.symbol.checkmark'), $r('app.string.index_guide_page_step_refresh_title'))
        }
        .indicator(new DotIndicator().color($r('sys.color.font_tertiary')).selectedColor($r('app.color.brand')))
        .loop(false)
        .layoutWeight(1)
        .onChange((index: number): void => {
          this.guideIndex = index;
        })

        Row() {
          Button($r('app.string.index_guide_page_skip'))
            .type(ButtonType.Normal)
            .backgroundColor(Color.Transparent)
            .fontColor($r('sys.color.font_secondary'))
            .visibility(this.guideIndex >= GUIDE_STEPS - 1 ? Visibility.None : Visibility.Visible)
            .onClick(() => {
              this.isGuideVisible = false;
            })

          Blank()

          Button(this.guideIndex >= GUIDE_STEPS - 1 ? $r('app.string.index_guide_page_start') :
            $r('app.string.index_guide_page_next'))
            .type(ButtonType.Capsule)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('sys.color.font_on_primary'))
            .onClick(() => {
              if (this.guideIndex >= GUIDE_STEPS - 1) {
                this.isGuideVisible = false;

                return;
              }

              this.guideSwiper.showNext();
            })
        }
        .width('100%')
        .padding({
          left: $r('app.integer.page_padding'),
          right: $r('app.integer.page_padding'),
          bottom: $r('app.integer.page_padding')
        })
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  guideStep(icon: Resource, title: Resource) {
    Column() {
      Text() {
        SymbolSpan(icon)
      }
      .fontSize(100)
      .fontColor($r('app.color.brand'))

      Text(title)
        .margin({ top: 30 })
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: $r('app.integer.page_padding'), right: $r('app.integer.page_padding') })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  guideActionStep(icon: Resource, title: Resource, actionText: Resource, action: () => void) {
    Column() {
      Text() {
        SymbolSpan(icon)
      }
      .fontSize(100)
      .fontColor($r('app.color.brand'))

      Text(title)
        .margin({ top: 30 })
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)

      Button(actionText)
        .type(ButtonType.Capsule)
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('sys.color.font_on_primary'))
        .margin({ top: 30 })
        .onClick(action)
    }
    .width('100%')
    .height('100%')
    .padding({ left: $r('app.integer.page_padding'), right: $r('app.integer.page_padding') })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  main() {
    Column() {
      this.header()

      if (this.isSortMode) {
        this.sortTip()
      }

      this.items()
    }
    .width('100%')
    .height('100%')
  }

  // 排序入口与列表统计放在内容区（与微信小程序一致）：胶囊占据顶部右侧，标题栏不适合再放控件
  @Builder
  header() {
    Row() {
      Text($r('app.string.index_index_page_total', this.itemsRuntime.ids.length))
        .fontSize(13)
        .fontColor($r('sys.color.font_tertiary'))

      Blank()

      Button(this.isSortMode ? $r('app.string.index_index_page_sort_mode_done') :
        $r('app.string.index_index_page_edit'))
        .type(ButtonType.Normal)
        .height(32)
        .padding({ left: 0, right: 0 })
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.brand'))
        .fontSize(14)
        .onClick(() => {
          if (this.isSortMode) {
            this.saveSort().catch(() => {
              // 失败已由 Toast 提示，仅避免 unhandled rejection
            });

            return;
          }

          this.enterSortMode();
        })
    }
    .width('100%')
    .padding({
      left: $r('app.integer.page_padding'),
      right: $r('app.integer.page_padding'),
      top: $r('app.integer.page_padding_smaller'),
      bottom: $r('app.integer.page_padding_smaller')
    })
  }

  @Builder
  sortTip() {
    Row() {
      Text($r('app.string.index_index_page_sort_tip'))
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: $r('app.integer.page_padding_smaller') })
  }

  @Builder
  items() {
    List({ scroller: this.scroller }) {
      Repeat<string>(this.itemsRuntime.ids)
        .each((ri: RepeatItem<string>) => {
          ListItem() {
            Column() {
              Row() {
                if (this.isSortMode) {
                  SymbolGlyph($r('sys.symbol.line_3_horizontal'))
                    .fontSize(24)
                    .fontColor([$r('sys.color.font_tertiary')])
                    .margin({ right: 10 })
                }

                Column() {
                  Column() {
                    Text(this.itemsRuntime.get(ri.item.valueOf()).issuer)
                      .fontSize(30)
                      .fontColor($r('sys.color.font_secondary'))
                      .textAlign(TextAlign.Center)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }

                  Column() {
                    Text(this.itemsRuntime.get(ri.item.valueOf()).username)
                      .fontSize(12)
                      .fontColor($r('sys.color.font_tertiary'))
                      .textAlign(TextAlign.Center)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .margin({ top: 5 })
                }
                .layoutWeight(4)

                Column() {
                  Text(this.itemsRuntime.get(ri.item.valueOf()).code)
                    .fontSize(50)
                }
                .layoutWeight(6)
              }
              .height(98)
              .padding({ left: $r('app.integer.page_padding_smaller'), right: $r('app.integer.page_padding_smaller') })

              Progress({
                value: this.itemsRuntime.get(ri.item.valueOf()).progress ?? 30,
                total: this.itemsRuntime.get(ri.item.valueOf()).config?.period ?? 30,
                type: ProgressType.Linear,
              })
                .height(2)
                .color($r('app.color.brand'))
            }
          }
          .borderRadius(10)
          .height(100)
          .backgroundColor($r('sys.color.background_primary'))
          .swipeAction(this.isSortMode ? undefined : {
            end: {
              builder: () => {
                this.swipeAction(ri.item.valueOf())
              },
            },
            edgeEffect: SwipeEdgeEffect.None,
          })
          .onAttach(() => {
            this.itemsRuntime.start(ri.item.valueOf());
          })
          .onDetach(() => {
            this.itemsRuntime.stop(ri.item.valueOf());
          })
          .onClick(() => {
            if (this.isSortMode) {
              return;
            }
            this.pages.pushPathByName(AppPagesName.INDEX_DETAIL,
              new ItemRuntime(this.itemsRuntime.get(ri.item.valueOf())))
          })
        })
        // 键值需稳定唯一，拖拽落位动画依赖它（缺省时 Repeat 会生成随机键值）
        .key((id: string): string => id)
        // 拖拽排序由框架接管：仅排序态开启，长按浮起后拖动，离手时在回调中同步数据顺序
        .onMove(this.isSortMode ? (from: number, to: number): void => {
          hilog.info(LogDomain.PAGES, AppPagesName.INDEX, '拖拽排序: %{public}d -> %{public}d', from, to);

          this.itemsRuntime.move(from, to);
        } : undefined)
      .virtualScroll({ totalCount: this.itemsRuntime.ids.length })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  swipeAction(id: string) {
    Row() {
      Button() {
        Text($r("app.string.index_index_page_detail_name"))
          .fontColor($r('sys.color.font_on_primary'))
      }
      .height('100%')
      .width(60)
      .type(ButtonType.Normal)
      .backgroundColor($r('app.color.brand'))
      .onClick(() => {
        this.pages.pushPathByName(AppPagesName.INDEX_DETAIL, new ItemRuntime(this.itemsRuntime.get(id)));

        try {
          this.scroller.closeAllSwipeActions();
        } catch (error) {
          hilog.error(LogDomain.PAGES, AppPagesName.INDEX, '调用 `closeAllSwipeActions` 失败')
        }
      })

      Button() {
        Text($r("app.string.index_index_page_delete_name")).fontColor($r('sys.color.font_on_primary'))
      }
      .height('100%')
      .width(60)
      .type(ButtonType.Normal)
      .backgroundColor($r('sys.color.warning'))
      .onClick(() => {
        this.swipeActionId = id;

        Dialog.open(() => this.deleteDialog());
      })
    }
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
    const items =
      await Dialog.execute(() => this.loadingDialog($r('app.string.loading')), () => Totp.all(),
        () => this.fetchFailedDialog(() => this.refresh()));

    this.itemsRuntime.reload(items.values());
    this.decideGuide();
  }
}
