import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { App, AppPagesName } from '../../App';
import { Card, CardItem } from '../../components/Card';
import { ItemsRuntime } from '../../models/Runtime';
import { User } from '../../models/User';
import { displayOr } from '../../utils/Display';

@Builder
export function builder() {
  Index()
}

@ComponentV2
struct Index {
  @Local
  private user: User =
    PersistenceV2.globalConnect({ type: User, defaultCreator: () => new User() })!;
  @Local
  private itemsRuntime: ItemsRuntime = AppStorageV2.connect(ItemsRuntime, () => new ItemsRuntime())!;

  build() {
    NavDestination() {
      Column({ space: $r('app.integer.column_space') }) {
        Column({ space: $r('app.integer.column_space_smaller') }) {
          Image(displayOr(this.user.config.avatar, $r('app.media.default_avatar'))).width('25%')
          Text(displayOr(this.user.config.nickname, $r('app.string.default_nickname')))
            .fontWeight(FontWeight.Bold)
        }

        Text($r('app.string.user_index_page_protected', this.protectedCount))
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('sys.color.font_tertiary'))

        Card({
          items: [
            new CardItem({
              title: $r('app.string.user_page_information'),
              value: '',
              eventClick: { action: AppPagesName.USER_DETAIL },
            }),
            new CardItem({
              title: $r('app.string.user_index_page_help'),
              value: '',
              eventClick: { action: AppPagesName.USER_HELP },
            }),
            new CardItem({
              title: $r('app.string.user_index_page_about'),
              value: $r('app.string.user_index_page_version', App.version),
            }),
          ]
        })
      }
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .title($r('app.string.user_index_page_name'))
    .mode(NavDestinationMode.DIALOG)
  }

  // 统计行兜底：user 页可能在 ItemsRuntime 未初始化时进入，ids 缺失时按 0 展示
  private get protectedCount(): number {
    const ids: string[] | undefined = this.itemsRuntime.ids;

    return 'undefined' === typeof ids ? 0 : ids.length;
  }
}
