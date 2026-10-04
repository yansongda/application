// 卡片数据桥接（单一入口）：快照装配 / 主动推送，主应用与 FormExtensionAbility 共用，
// 避免 formBindingData 装配散落多处（此前在提供方 2 处 + 首页 1 处重复实现）。
// 注意：卡内只注入字符串（跨进程数据只能以字符串传递），且不得出现密钥 / 验证码。
//
// 注入契约：卡片使用状态管理 V2，注入字段按「变量名」匹配 pages/card/Card.ets 的 @Local 变量，
// 因此下面两个常量必须与那侧的变量名逐字一致；key 写错不会编译报错，只会静默不刷新。
// 空态不再单独注入标记字段：卡片侧以 count == '0' 推导（避免两处状态互相不同步）。
import { Context } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardSnapshot, CardSnapshotData, CardSnapshotItem } from '../../utils/CardSnapshot';
import { LogDomain } from '../../App';

// 注入字段名（= 卡片侧 @Local 变量名）
export const CARD_FIELD_COUNT: string = 'count';
export const CARD_FIELD_FIRST: string = 'first';

export class CardBridge {
  // 装配卡片绑定数据：onAddForm / onUpdateForm / 主应用主动推送共用同一份口径
  static bindingData(snap: CardSnapshotData): formBindingData.FormBindingData {
    const data: Record<string, string> = {};

    data[CARD_FIELD_COUNT] = String(snap.count);
    data[CARD_FIELD_FIRST] = snap.items[0]?.issuer ?? '';

    hilog.info(LogDomain.MODELS, 'models/card/CardBridge', '装配卡片数据: count=%{public}s',
      data[CARD_FIELD_COUNT]);

    return formBindingData.createFormBindingData(data);
  }

  // 账号列表变化后：写快照并推送全部已添加卡片
  static sync(context: Context, items: CardSnapshotItem[]): void {
    hilog.info(LogDomain.MODELS, 'models/card/CardBridge', '卡片同步: 账号数=%{public}d', items.length);

    CardSnapshot.write(context, items);

    CardBridge.push(context);
  }

  // 主动推送最新快照；formIds 缺省时推送所有已添加卡片；失败仅记日志，不打断主流程
  static push(context: Context, formIds?: string[]): void {
    const formTargets: string[] = formIds ?? CardSnapshot.listFormIds(context);

    // 便于排查「卡片不刷新」：目标为空说明 formId 没读到（跨进程缓存 / 卡片未添加）
    hilog.info(LogDomain.MODELS, 'models/card/CardBridge', '卡片推送: 目标数=%{public}d, targets=%{public}s',
      formTargets.length, JSON.stringify(formTargets));

    if (formTargets.length <= 0) {
      return;
    }

    const data: formBindingData.FormBindingData = CardBridge.bindingData(CardSnapshot.read(context));

    formTargets.forEach((formId: string): void => {
      formProvider.updateForm(formId, data).then(() => {
        hilog.info(LogDomain.MODELS, 'models/card/CardBridge', '卡片推送成功: formId=%{public}s', formId);
      }).catch((e: Error) => {
        hilog.error(LogDomain.MODELS, 'models/card/CardBridge', '卡片推送失败: formId=%{public}s, err=%{public}s',
          formId, JSON.stringify(e));
      });
    });
  }
}
