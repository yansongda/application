import { ItemRuntime, ItemsRuntime } from '../../models/Runtime';
import {
  AdvancedDialogV2Button,
  AlertDialogV2,
  AppStorageV2,
  LoadingDialogV2,
  PersistenceV2,
  SymbolGlyphModifier,
  promptAction
} from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Authorization } from '../../models/Auth';
import { Dialog } from '../../utils/PromptAction';
import { AppPagesName, LogDomain } from '../../App';
import { Totp } from '../../api/Totp';
import { scanBarcode } from '@kit.ScanKit';
import { User } from '../../models/User';
import { User as UserApi } from '../../api/User';

@ObservedV2
export class IndexGuideState {
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
  @Local
  private draggedIndex: number = -1;
  private snapshotIds: string[] = [];
  @Local
  private itemsRuntime: ItemsRuntime = new ItemsRuntime();
  private user: User =
    PersistenceV2.globalConnect({ type: User, defaultCreator: () => new User() })!;
  private scroller: ListScroller = new ListScroller();
  private swipeActionId?: string;
  private pages: NavPathStack = AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;

  @Monitor('authorization.accessToken')
  async onAuthorizationChange(): Promise<void> {
    hilog.info(LogDomain.PAGES, AppPagesName.INDEX, '监测到认证信息发生变化');

    const user = await UserApi.detail();

    this.user.phone = user.phone;
    this.user.config = user.config;
  }

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
          this.refresh();

          this.isRefreshing = false;
        })
        .refreshOffset(64)
        .pullToRefresh(true)

        if (!this.isSortMode) {
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
              value: '扫码添加',
              symbolIcon: new SymbolGlyphModifier($r('sys.symbol.line_viewfinder')),
              action: () => {
                scanBarcode.startScanForResult(this.getUIContext().getHostContext()).then(async (result) => {
                  let uri = result.originalValue;

                  hilog.info(LogDomain.PAGES, AppPagesName.INDEX, '扫码结果: %{public}s', uri);

                  try {
                    const data =
                      await Dialog.execute(() => this.loadingDialog($r('app.string.handling')),
                        () => Totp.create(uri));

                    this.itemsRuntime.add(data);
                  } catch (e) {
                    await Dialog.open(() => this.addFailedDialog(e.message));
                  }
                });
              },
            },
            {
              value: '输入添加',
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

      this.refresh();
    })
    .onHidden(() => {
      hilog.info(LogDomain.PAGES, AppPagesName.INDEX, '页面隐藏');

      this.itemsRuntime.clear();
    })
  }

  @Builder
  title() {
    Row() {
      if (this.isSortMode) {
        Text("拖拽排序中")
          .fontWeight(FontWeight.Bold)
          .fontSize(20)
          .layoutWeight(1)

        Button("完成")
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('sys.color.font_on_primary'))
          .onClick(async () => {
            let reqItems: Array<{ id: string, sort: number }> = [];
            let len = this.itemsRuntime.ids.length;
            this.itemsRuntime.ids.forEach((id, idx) => {
              reqItems.push({ id: id, sort: len - 1 - idx });
            });

            try {
              const dialogId = await Dialog.open(() => this.loadingDialog());
              await Totp.sort(reqItems);
              Dialog.close(dialogId);
              this.isSortMode = false;
            } catch (e) {
              this.itemsRuntime.ids.splice(0, this.itemsRuntime.ids.length, ...this.snapshotIds);
              promptAction.showToast({ message: '排序失败: ' + e.message });
            }
          })
      } else {
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

        Blank()

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_up_arrow_down'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
        }
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.isSortMode = true;
          this.snapshotIds = [...this.itemsRuntime.ids];
        })
      }
    }
    .width('100%')
    .height('100%')
    .margin({ left: 10, right: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  guide() {
    if (this.guideState.isSkipped) {
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
      Stack({ alignContent: Alignment.TopEnd }) {
        Stepper() {
          StepperItem() {
            Column() {
              Text() {
                SymbolSpan($r('sys.symbol.shield'))
              }
              .fontSize(100)
              .fontColor([$r('app.color.brand')])
              
              Text("MFA 验证器保护账号安全")
                .margin({ top: 30 })
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }
          .nextLabel('下一步')
          .prevLabel('上一步')
          
          StepperItem() {
            Column() {
              Text() {
                SymbolSpan($r('sys.symbol.qrcode'))
              }
              .fontSize(100)
              .fontColor([$r('app.color.brand')])
              
              Button("扫码添加")
                .margin({ top: 30 })
                .onClick(() => {
                  scanBarcode.startScanForResult(this.getUIContext().getHostContext()).then(async (result) => {
                    let uri = result.originalValue;

                    hilog.info(LogDomain.PAGES, AppPagesName.INDEX, '扫码结果: %{public}s', uri);

                    try {
                      const data =
                        await Dialog.execute(() => this.loadingDialog($r('app.string.handling')),
                          () => Totp.create(uri));

                      this.itemsRuntime.add(data);
                    } catch (e) {
                      await Dialog.open(() => this.addFailedDialog(e.message));
                    }
                  });
                })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }
          .nextLabel('下一步')
          .prevLabel('上一步')
          
          StepperItem() {
            Column() {
              Text() {
                SymbolSpan($r('sys.symbol.doc_plaintext_and_pencil'))
              }
              .fontSize(100)
              .fontColor([$r('app.color.brand')])
              
              Button("手动输入")
                .margin({ top: 30 })
                .onClick(() => {
                  this.pages.pushPathByName(AppPagesName.INDEX_CREATE, null);
                })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }
          .nextLabel('下一步')
          .prevLabel('上一步')
          
          StepperItem() {
            Column() {
              Text() {
                SymbolSpan($r('sys.symbol.checkmark'))
              }
              .fontSize(100)
              .fontColor([$r('app.color.brand')])
              
              Text("验证码每 30 秒刷新")
                .margin({ top: 30 })
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }
          .nextLabel('开始使用')
          .prevLabel('上一步')
        }
        .onFinish(() => {
          this.guideState.isSkipped = true;
        })
        .onSkip(() => {
          this.guideState.isSkipped = true;
        })
        
        Button("跳过")
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.font_secondary'))
          .margin({ top: 20, right: 20 })
          .onClick(() => {
            this.guideState.isSkipped = true;
          })
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  dragPreview(id: string) {
    Column() {
      Text(this.itemsRuntime.get(id).issuer)
        .fontSize(30)
        .fontColor($r('sys.color.font_secondary'))
    }
    .padding(10)
    .borderRadius(10)
    .backgroundColor($r('sys.color.background_primary'))
  }

  @Builder
  main() {
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
          .onDragStart((event: DragEvent, extraParams: string) => {
            if (!this.isSortMode) {
              return;
            }
            this.draggedIndex = ri.index;
            return this.dragPreview(ri.item.valueOf());
          })
          .onDrop((event: DragEvent, extraParams: string) => {
            if (!this.isSortMode) {
              return;
            }
            let targetIndex = ri.index;
            if (this.draggedIndex !== -1 && this.draggedIndex !== targetIndex) {
              this.itemsRuntime.move(this.draggedIndex, targetIndex);
              this.draggedIndex = -1;
            }
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
      .virtualScroll({ totalCount: this.itemsRuntime.ids.length })
    }
    .width('100%')
    .height('100%')
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

  private async refresh(): Promise<void> {
    this.itemsRuntime.clear();

    const items =
      await Dialog.execute(() => this.loadingDialog($r('app.string.loading')), () => Totp.all(),
        () => this.fetchFailedDialog(() => this.refresh()));

    this.itemsRuntime = new ItemsRuntime(items.values());
  }
}
