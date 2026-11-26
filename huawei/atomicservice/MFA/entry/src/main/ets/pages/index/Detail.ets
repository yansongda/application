import { application } from '@kit.AbilityKit';
import { AppStorageV2, LoadingDialogV2 } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ItemRuntime } from '../../models/totp/ItemRuntime';
import { ItemsRuntime } from '../../models/totp/ItemsRuntime';
import { AppPagesName, LogDomain } from '../../App';
import { Totp } from '../../api/Totp';
import { EditTextParams } from './EditText';
import { TagParams } from './Tag';
import { IInfoCardJumpResult, InfoCard, InfoCardItem } from '../../components/InfoCard';
import { Clipboard } from '../../utils/Clipboard';
import { collectTags } from '../../utils/ItemFilter';
import { Toast } from '../../utils/PromptAction';

@Builder
export function builder() {
  Detail()
}

@ComponentV2
struct Detail {
  // 与列表**同一个**运行时实例（按 id 从 ItemsRuntime 取），不再复制：
  // 历史实现传 `new ItemRuntime(...)` 副本，导致「详情页改了标签/置顶，列表不更新」要靠一次网络刷新才同步，
  // 且明文 secret 在内存里存了两份。占位实例（id 为空）只用于 onReady 之前的首帧。
  private runtime: ItemRuntime = ItemRuntime.empty();
  private pages: NavPathStack = AppStorageV2.connect(NavPathStack, () => new NavPathStack())!;
  @Local
  private itemsRuntime: ItemsRuntime = AppStorageV2.connect(ItemsRuntime, () => new ItemsRuntime())!;

  build() {
    NavDestination() {
      // 整页滚动：卡片总高可能超过一屏（小屏 / 大字号），避免底部入口不可触达
      Scroll() {
        Column({ space: $r('app.integer.column_space') }) {
          Column() {
            Progress({
              value: this.runtime.remaining,
              total: this.runtime.config.period,
              type: ProgressType.Linear
            })
              .height(2)
              .color($r('app.color.brand'))

            Text(this.runtime.code ?? $r('app.string.index_detail_page_value_unknown'))
              .textAlign(TextAlign.Center)
              .fontSize(70)
              .width('100%')
              .maxLines(1)
              .maxFontSize(70)
              .minFontSize(40)
              .margin({ top: 20 })

            Button($r('app.string.index_detail_page_copy'))
              .type(ButtonType.Capsule)
              .margin({ top: 20 })
              .onClick(async () => {
                const code = this.runtime.code;

                if ('undefined' === typeof code || code.length === 0) {
                  return;
                }

                try {
                  await Clipboard.copy(code);
                  Toast.show({ message: $r('app.string.index_index_page_copied'), duration: 3000 });
                } catch (e) {
                  Toast.show({ message: $r('app.string.index_index_page_copy_failed'), duration: 3000 });
                }
              })
          }

          InfoCard({
            title: $r('app.string.index_page_basic_information'),
            items: [
              new InfoCardItem({
                title: $r('app.string.index_page_issuer'),
                value: this.runtime.issuer.length > 0 ? this.runtime.issuer :
                  $r('app.string.index_detail_page_value_unknown'),
                eventClick: { action: AppPagesName.INDEX_EDIT_ISSUER, params: new EditTextParams(this.runtime, true) },
              }),
              new InfoCardItem({
                title: $r('app.string.index_page_username'),
                value: this.runtime.username.length > 0 ? this.runtime.username :
                  $r('app.string.index_detail_page_value_unknown'),
                eventClick: { action: AppPagesName.INDEX_EDIT_USERNAME, params: new EditTextParams(this.runtime, false) },
              }),
            ]
          })

          InfoCard({
            title: $r('app.string.index_detail_page_organization'),
            items: [
              new InfoCardItem({
                title: $r('app.string.index_page_tag'),
                value: this.tagDisplay(this.runtime.tag),
                eventClick: {
                  action: (): Promise<string> => this.openTagPage(),
                },
              }),
              new InfoCardItem({
                title: $r('app.string.index_page_pinned'),
                value: this.pinDisplay(this.runtime.pinned),
                eventClick: {
                  action: async (): Promise<string | undefined> => this.togglePinned(),
                },
              }),
            ]
          })

          InfoCard({
            title: $r('app.string.index_page_config_information'),
            items: [
              new InfoCardItem({
                title: $r('app.string.index_page_config_period'),
                value: this.runtime.config.period.toString() + 's',
              }),
              new InfoCardItem({
                title: $r('app.string.index_page_config_digits'),
                value: this.runtime.config.digits.toString() + ' 位',
              }),
              new InfoCardItem({
                title: $r('app.string.index_page_config_algorithm'),
                value: this.runtime.config.algorithm.toString(),
              }),
            ]
          })

          // 全局用法说明统一收敛到「使用帮助」页，本页只保留入口：详情页承载全局说明会与帮助页重复
          InfoCard({
            items: [
              new InfoCardItem({
                title: $r('app.string.help_entry'),
                value: '',
                eventClick: { action: AppPagesName.HELP },
              }),
            ]
          })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .title($r('app.string.index_detail_page_title'))
    .onReady((context: NavDestinationContext) => {
      // 路由参数是条目 id（不是运行时副本）：从 ItemsRuntime 取同一个实例
      const id = context.pathInfo.param as string;

      if ('string' === typeof id && id.length > 0) {
        this.runtime = this.itemsRuntime.get(id);
      }
    })
    // 计时与算码不在这里起停：时间来自全局 Clock（起停只由前后台驱动），
    // 页面切到前台/后台不影响任何一行的验证码刷新。
  }

  @Builder
  loadingDialog() {
    LoadingDialogV2({
      content: $r('app.string.handling'),
    })
  }

  // 标签行：push 标签页并等待 pop；返回给 InfoCard 的展示值，同时同步 runtime.tags
  private openTagPage(): Promise<string> {
    const runtime = this.runtime;

    return new Promise<string>((resolve) => {
      this.pages.pushPathByName(AppPagesName.INDEX_EDIT_TAG,
        new TagParams(runtime.id, runtime.tags, collectTags(this.itemsRuntime.snapshot())),
        (popInfo: PopInfo) => {
          const result = popInfo.result as IInfoCardJumpResult | undefined | null;
          const tag = ('undefined' !== typeof result && null !== result) ? result.value : runtime.tag;

          runtime.tags = tag.length > 0 ? [tag] : [];
          resolve(this.tagDisplay(tag));
        });
    });
  }

  // 置顶行：先请求、成功才改内存；失败返回 undefined，InfoCard 保持原值
  private async togglePinned(): Promise<string | undefined> {
    const runtime = this.runtime;

    const next = !runtime.pinned;

    try {
      await Toast.execute(
        () => Totp.editPinned(runtime.id, next),
        () => this.loadingDialog()
      );

      runtime.pinned = next;

      return this.pinDisplay(next);
    } catch (e) {
      hilog.warn(LogDomain.PAGES, AppPagesName.INDEX_DETAIL, '切换置顶失败: %{public}s', JSON.stringify(e));

      return undefined;
    }
  }

  private tagDisplay(tag: string): string {
    return tag.length > 0 ? `#${tag}` : this.stringOf($r('app.string.index_page_tag_unset'));
  }

  private pinDisplay(on: boolean): string {
    return this.stringOf(on ? $r('app.string.index_detail_page_pinned_on') :
      $r('app.string.index_detail_page_pinned_off'));
  }

  private stringOf(resource: Resource): string {
    try {
      return application.getApplicationContext().resourceManager.getStringSync(resource.id);
    } catch (e) {
      return '';
    }
  }
}
