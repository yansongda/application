import { PersistenceV2 } from '@kit.ArkUI';
import { AppPagesName } from '../../App';
import { Card, CardItem } from '../../components/Card';
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

  build() {
    NavDestination() {
      Column({ space: $r('app.integer.column_space') }) {
        Column({ space: $r('app.integer.column_space_smaller') }) {
          Image(displayOr(this.user.config.avatar, $r('app.media.default_avatar'))).width('25%')
          Text(displayOr(this.user.config.nickname, $r('app.string.default_nickname')))
            .fontWeight(FontWeight.Bold)
        }

        Card({
          items: [
            new CardItem({
              title: $r('app.string.user_page_information'),
              value: '',
              eventClick: { action: AppPagesName.USER_DETAIL },
            }),
          ]
        })
      }
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .title($r('app.string.user_index_page_name'))
    .mode(NavDestinationMode.DIALOG)
  }
}