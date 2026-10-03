import { ItemRuntime } from '../../models/Runtime';
import { AppPagesName } from '../../App';
import { EditTextParams } from './edit/Text';
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

        Card({
          title: $r('app.string.index_detail_page_usage_title'),
          items: [
            new CardItem({ title: $r('app.string.index_detail_page_usage_offline'), value: '' }),
            new CardItem({ title: $r('app.string.index_detail_page_usage_period'), value: '' }),
            new CardItem({ title: $r('app.string.index_detail_page_usage_delete'), value: '' }),
            new CardItem({ title: $r('app.string.index_detail_page_usage_card'), value: '' }),
          ]
        })
      }
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
    .onHidden(() => {
      this.runtime = undefined;
    })
  }
}