// 卡片数据桥接（单一入口）：装配绑定数据 / 主动推送，主应用与 FormExtensionAbility 共用。
// 卡内只注入字符串（跨进程数据只能以字符串传递），且不得出现密钥 / 验证码。
//
// 注入契约：卡片用状态管理 V2，注入字段按「变量名」匹配 pages/form/Form2x2.ets 的 @Local 变量，
// 故下面常量必须与那侧变量名逐字一致；写错不会编译报错，只会静默不刷新。
// 空态不单独注入标记字段，卡片侧以 count == '0' 推导。
import { Context } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Snapshot, SnapshotData } from '../../utils/Form';
import { LogDomain } from '../../App';

// formProvider.updateForm 错误码：要操作的卡片 ID 不存在（本地残留了已失效的 formId）
const ERR_FORM_ID_NOT_EXIST: number = 16501001;

// 注入字段名（= 卡片侧 @Local 变量名）
export const FORM_FIELD_COUNT: string = 'count';

export class FormBridge {
  // 装配卡片绑定数据：onAddForm / onUpdateForm / 主应用主动推送共用同一份口径
  static bindingData(snap: SnapshotData): formBindingData.FormBindingData {
    const data: Record<string, string> = {};

    data[FORM_FIELD_COUNT] = String(snap.count);

    hilog.info(LogDomain.MODELS, 'models/form/FormBridge', '装配卡片数据: count=%{public}s',
      data[FORM_FIELD_COUNT]);

    return formBindingData.createFormBindingData(data);
  }

  // 账号列表变化后：写快照并推送全部已添加卡片
  static sync(context: Context, ids: string[]): void {
    hilog.info(LogDomain.MODELS, 'models/form/FormBridge', '卡片同步: 账号数=%{public}d', ids.length);

    Snapshot.write(context, ids.length);

    FormBridge.push(context);
  }

  // 主动推送最新快照；formIds 缺省时推送所有已添加卡片；失败仅记日志，不打断主流程。
  // 系统侧已不存在该卡片（16501001）时清理本地 formId，避免每次启动/刷新重复失败。
  static push(context: Context, formIds?: string[]): void {
    const formTargets: string[] = formIds ?? Snapshot.listFormIds(context);

    // 便于排查「卡片不刷新」：目标为空说明 formId 没读到（跨进程缓存 / 卡片未添加）
    hilog.info(LogDomain.MODELS, 'models/form/FormBridge', '卡片推送: 目标数=%{public}d, targets=%{public}s',
      formTargets.length, JSON.stringify(formTargets));

    if (formTargets.length <= 0) {
      return;
    }

    const data: formBindingData.FormBindingData = FormBridge.bindingData(Snapshot.read(context));

    formTargets.forEach((formId: string): void => {
      formProvider.updateForm(formId, data).then(() => {
        hilog.info(LogDomain.MODELS, 'models/form/FormBridge', '卡片推送成功: formId=%{public}s', formId);
      }).catch((e: BusinessError) => {
        // 16501001 = 要操作的卡片 ID 不存在：常见于卡片被移除但 onRemoveForm 未回调、
        // 调试替换安装或卡片名变更后旧 formId 失效；属陈旧数据，清理后不再重试
        if (e.code === ERR_FORM_ID_NOT_EXIST) {
          Snapshot.removeFormId(context, formId);
          hilog.warn(LogDomain.MODELS, 'models/form/FormBridge',
            '卡片已不存在，已清理 formId: formId=%{public}s', formId);

          return;
        }

        hilog.error(LogDomain.MODELS, 'models/form/FormBridge', '卡片推送失败: formId=%{public}s, err=%{public}s',
          formId, JSON.stringify(e));
      });
    });
  }
}
