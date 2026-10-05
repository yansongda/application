// 卡片意图（主应用侧）：EntryAbility 解析 postCardAction(router) 的 want 参数后写入，
// Index 页通过 @Monitor('formIntent.version') 感知并消费。
// 当前路由：'scan' = 直达扫码添加；'input' = 直达手动输入添加页。
// 注意：postCardAction 的 params 被整体包装为 want.parameters.params（JSON 字符串），不逐键平铺；
// 日志不得出现 token / 密钥 / 验证码。
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../../App';

@ObservedV2
export class FormIntent {
  // 卡片意图路由：'scan' = 扫码添加；'input' = 手动输入添加；缺省（普通点卡）视为仅打开应用
  @Trace
  route?: string;

  // 每次写入自增，供页面 @Monitor 感知
  @Trace
  version: number = 0;

  // 按官方契约解析 want：params 被整体包装为 want.parameters.params（JSON 字符串）。
  // params 不存在 → 返回 undefined（普通点卡，无快捷意图）；JSON.parse 失败视为实现 bug，打点后忽略。
  static fromWant(want: Want): string | undefined {
    const raw = want?.parameters?.params;

    if ('string' !== typeof raw) {
      return undefined;
    }

    try {
      const params: Record<string, string> = JSON.parse(raw) as Record<string, string>;

      return params.mfa_route;
    } catch (e) {
      hilog.error(LogDomain.MODELS, 'models/form/FormIntent', '卡片意图参数解析失败: %{public}s',
        JSON.stringify(e));

      return undefined;
    }
  }
}
