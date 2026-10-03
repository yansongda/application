import { ItemRuntime } from '../../models/Runtime';
import { AppPagesName } from '../../App';
import { EditTextParams } from './EditText';
import { Card, CardItem } from '../../components/Card';
import { Clipboard } from '../../utils/Clipboard';
import { Toast } from '../../utils/PromptAction';

@Builder
export function builder() {
  Detail()
}

@ComponentV2
struct Detail {
  private runtime: ItemRuntime | undefined = undefined;

  build() {
    NavDestination() {
      // 整页滚动：卡片总高可能超过一屏（小屏 / 大字号），避免底部入口不可触达
      Scroll() {
        Column({ space: $r('app.integer.column_space') }) {
          Column() {
            Progress({
              value: this.runtime?.progress ?? 0,
              total: this.runtime?.config.period ?? 30,
              type: ProgressType.Linear
            })
              .height(2)
              .color($r('app.color.brand'))

            Text(this.runtime?.code ?? $r('app.string.index_detail_page_value_unknown'))
              .textAlign(TextAlign.Center)
              .fontSize(70)
              .margin({ top: 20 })

            Button($r('app.string.index_detail_page_copy'))
              .type(ButtonType.Capsule)
              .margin({ top: 20 })
              .onClick(async () => {
                const code = this.runtime?.code;

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

          Card({
            title: $r('app.string.index_page_basic_information'),
            items: [
              new CardItem({
                title: $r('app.string.index_page_issuer'),
                value: this.runtime?.issuer ?? $r('app.string.index_detail_page_value_unknown'),
                eventClick: { action: AppPagesName.INDEX_EDIT_ISSUER, params: new EditTextParams(this.runtime, true) },
              }),
              new CardItem({
                title: $r('app.string.index_page_username'),
                value: this.runtime?.username ?? $r('app.string.index_detail_page_value_unknown'),
                eventClick: { action: AppPagesName.INDEX_EDIT_USERNAME, params: new EditTextParams(this.runtime, false) },
              }),
            ]
          })

          Card({
            title: $r('app.string.index_page_config_information'),
            items: [
              new CardItem({
                title: $r('app.string.index_page_config_period'),
                value: (this.runtime?.config.period ?? '30').toString() + 's',
              }),
            ]
          })

          // 全局用法说明统一收敛到「使用帮助」页，本页只保留入口：详情页承载全局说明会与帮助页重复
          Card({
            items: [
              new CardItem({
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
      this.runtime = context.pathInfo.param as ItemRuntime;
    })
    .onActive(() => {
      this.runtime?.start();
    })
    .onInactive(() => {
      this.runtime?.stop();
    })
    // 不在此处清空 runtime：onReady 仅在 NavDestination 创建时触发一次，清空后返回时无法恢复，
    // onActive 重启定时器会变成空操作（验证码与进度条卡死）；停表已由 onInactive 负责
  }
}
