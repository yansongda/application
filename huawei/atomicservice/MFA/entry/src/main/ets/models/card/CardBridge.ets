// 卡片数据桥接（单一入口）：快照装配 / 主动推送，主应用与 FormExtensionAbility 共用，
// 避免 formBindingData 装配散落多处（此前在提供方 2 处 + 首页 1 处重复实现）。
// 注意：卡内只注入字符串（跨进程数据只能以字符串传递），且不得出现密钥 / 验证码。
import { Context } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardSnapshot, CardSnapshotData, CardSnapshotItem } from '../../utils/CardSnapshot';
import { LogDomain } from '../../App';

export class CardBridge {
  // 装配卡片绑定数据：onAddForm / onUpdateForm / 主应用主动推送共用同一份口径
  static bindingData(snap: CardSnapshotData): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData({
      count: String(snap.count),
      first: snap.items[0]?.issuer ?? '',
      hasItems: snap.count > 0 ? '1' : '0',
    });
  }

  // 账号列表变化后：写快照并推送全部已添加卡片
  static sync(context: Context, items: CardSnapshotItem[]): void {
    CardSnapshot.write(context, items);

    CardBridge.push(context);
  }

  // 主动推送最新快照；formIds 缺省时推送所有已添加卡片；失败仅记日志，不打断主流程
  static push(context: Context, formIds?: string[]): void {
    const formTargets: string[] = formIds ?? CardSnapshot.listFormIds(context);

    if (formTargets.length <= 0) {
      return;
    }

    const data: formBindingData.FormBindingData = CardBridge.bindingData(CardSnapshot.read(context));

    formTargets.forEach((formId: string): void => {
      formProvider.updateForm(formId, data).catch((e: Error) => {
        hilog.error(LogDomain.MODELS, 'models/card/CardBridge', '卡片推送失败: formId=%{public}s, err=%{public}s',
          formId, JSON.stringify(e));
      });
    });
  }
}
