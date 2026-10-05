// 服务卡片生命周期（Form Kit）：onAddForm 落 formId 并从 preferences 快照装配初始数据；
// onRemoveForm 清除 formId；onUpdateForm 重读快照推送最新数据（fire-and-forget）。
// 注意：日志不得出现密钥 / 验证码。
import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';
import { Snapshot, SnapshotData } from '../utils/Form';
import { FormBridge } from '../models/form/FormBridge';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    // 提供方是非 UI 上下文，$r 不可用；快照装配全部同步，只注入字符串（跨进程数据只能以字符串传递）。
    const formId: string | undefined = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string;

    if (formId !== undefined) {
      Snapshot.addFormId(this.context, formId);
    }

    const snap: SnapshotData = Snapshot.read(this.context);

    hilog.info(LogDomain.FORM, 'ability/EntryFormAbility', 'onAddForm 回调. want: %{public}s',
      JSON.stringify(want));
    hilog.info(LogDomain.FORM, 'ability/EntryFormAbility', 'onAddForm 装配数据. formId: %{public}s, count: %{public}d',
      String(formId), snap.count);

    return FormBridge.bindingData(snap);
  }

  onRemoveForm(formId: string): void {
    Snapshot.removeFormId(this.context, formId);
    hilog.info(LogDomain.FORM, 'ability/EntryFormAbility', 'onRemoveForm 回调. formId: %{public}s', formId);
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    FormBridge.push(this.context, [formId]);
  }
}
