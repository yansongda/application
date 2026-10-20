// 卡片意图（主应用侧）：EntryAbility 解析 postCardAction(router) 的 want 参数后写入，
// Index 页通过 @Monitor('formIntent.version') 感知并消费。
// 路由定义见 FormRoute：FormRoute.SCAN = 直达扫码添加；FormRoute.INPUT = 直达手动输入添加页。
// 未登录 / 应用锁锁定 / 页面未激活时由 Index 暂缓消费，超过 TTL 后丢弃。
// 注意：postCardAction 的 params 被整体包装为 want.parameters.params（JSON 字符串），不逐键平铺；
// 日志不得出现 token / 密钥 / 验证码。
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../../App';
import { FORM_ROUTE_PARAM, FormRoute, parseFormRoute } from './FormRoute';

@ObservedV2
export class FormIntent {
  // 卡片意图路由；缺省（普通点卡）视为仅打开应用
  @Trace
  route?: FormRoute;

  // 每次写入自增，供页面 @Monitor 感知
  @Trace
  version: number = 0;

  // 意图产生时间（毫秒）：超过 TTL 的 pending 意图不再消费，
  // 避免用户取消解锁/登录后很久又突然触发
  @Trace
  createdAt: number = 0;

  // 按官方契约解析 want：params 被整体包装为 want.parameters.params（JSON 字符串）。
  // params 不存在 → 返回 undefined（普通点卡，无快捷意图）；未知路由 / JSON.parse 失败视为无意图，打点后忽略。
  static fromWant(want: Want): FormRoute | undefined {
    const raw = want?.parameters?.params;

    if ('string' !== typeof raw) {
      return undefined;
    }

    try {
      const params: Record<string, string> = JSON.parse(raw) as Record<string, string>;

      return parseFormRoute(params[FORM_ROUTE_PARAM]);
    } catch (e) {
      hilog.error(LogDomain.MODELS, 'models/form/FormIntent', '卡片意图参数解析失败: %{public}s',
        JSON.stringify(e));

      return undefined;
    }
  }
}
