// 服务卡片生命周期（Form Kit）：onAddForm 返回卡片初始数据（本轮为静态数据，Task 2 换成
// preferences 快照装配）；onRemoveForm / onUpdateForm 本轮仅打点（Task 2 补齐刷新内容）。
// 注意：日志不得出现 secret / 验证码。
import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    // 提供方是非 UI 上下文，$r 不可用，本轮用字面量；Task 2 换成快照装配。
    const data: Record<string, string> = {
      'title': 'MFA认证',
      'count': '0',
      'first': '',
      'hint': '点击查看验证码',
    };

    hilog.info(LogDomain.FORM, 'entryformability', 'onAddForm 回调. want: %{public}s', JSON.stringify(want));

    return formBindingData.createFormBindingData(data);
  }

  onRemoveForm(formId: string): void {
    hilog.info(LogDomain.FORM, 'entryformability', 'onRemoveForm 回调. formId: %{public}s', formId);
  }

  onUpdateForm(formId: string): void {
    hilog.info(LogDomain.FORM, 'entryformability', 'onUpdateForm 回调. formId: %{public}s', formId);
  }
}
