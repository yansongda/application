// 卡片动作（主应用侧）：EntryAbility 解析 postCardAction(router) 的 want 参数后写入，
// Index 页通过 @Monitor('cardAction.version') 感知并消费（点卡取码）。
// 注意：postCardAction 的 params 被整体包装为 want.parameters.params（JSON 字符串），不逐键平铺；
// 日志不得出现 token / 密钥 / 验证码。
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../../App';

@ObservedV2
export class CardAction {
  // 'copy'：复制首个账号验证码
  @Trace
  action?: string;

  // 指定账号 id（可选，缺省复制首个账号）
  @Trace
  itemId?: string;

  // 每次写入自增，供页面 @Monitor 感知
  @Trace
  version: number = 0;

  // 按官方契约解析 want：params 被整体包装为 want.parameters.params（JSON 字符串）。
  // params 完全不存在 → 返回 undefined（参数未到达）；JSON.parse 失败 = 键名/格式错误（实现 bug，打点）。
  static fromWant(want: Want): CardAction | undefined {
    const raw = want?.parameters?.params;

    if ('string' !== typeof raw) {
      return undefined;
    }

    let params: Record<string, string>;

    try {
      params = JSON.parse(raw) as Record<string, string>;
    } catch (e) {
      hilog.error(LogDomain.MODELS, 'models/card-action', '卡片动作参数解析失败: %{public}s', JSON.stringify(e));

      return undefined;
    }

    const action: string | undefined = params.mfa_action;

    if ('copy' !== action) {
      return undefined;
    }

    const cardAction = new CardAction();

    cardAction.action = action;
    cardAction.itemId = params.mfa_item_id;

    return cardAction;
  }
}
