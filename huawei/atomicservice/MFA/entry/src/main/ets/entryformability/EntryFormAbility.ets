// 服务卡片生命周期（Form Kit）：onAddForm 从 preferences 快照装配卡片初始数据并落 formId；
// onRemoveForm 清除 formId；onUpdateForm 重读快照推送最新数据（fire-and-forget）。
// 注意：日志不得出现密钥 / 验证码。
import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';
import { CardSnapshot, CardSnapshotData } from '../utils/CardSnapshot';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    // 提供方是非 UI 上下文，$r 不可用；快照装配全部同步，只注入字符串（跨进程数据只能以字符串传递）。
    const formId: string | undefined = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string;

    if (formId !== undefined) {
      CardSnapshot.addFormId(this.context, formId);
    }

    const snap: CardSnapshotData = CardSnapshot.read(this.context);

    hilog.info(LogDomain.FORM, 'entryformability', 'onAddForm 回调. want: %{public}s', JSON.stringify(want));

    return formBindingData.createFormBindingData({
      count: String(snap.count),
      first: snap.items[0]?.issuer ?? '',
      hasItems: snap.count > 0 ? '1' : '0',
    });
  }

  onRemoveForm(formId: string): void {
    CardSnapshot.removeFormId(this.context, formId);
    hilog.info(LogDomain.FORM, 'entryformability', 'onRemoveForm 回调. formId: %{public}s', formId);
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    const snap: CardSnapshotData = CardSnapshot.read(this.context);
    const data: formBindingData.FormBindingData = formBindingData.createFormBindingData({
      count: String(snap.count),
      first: snap.items[0]?.issuer ?? '',
      hasItems: snap.count > 0 ? '1' : '0',
    });

    formProvider.updateForm(formId, data).catch((e: Error) => {
      hilog.error(LogDomain.FORM, 'entryformability', 'updateForm 推送失败. formId: %{public}s, err: %{public}s',
        formId, JSON.stringify(e));
    });
  }
}
