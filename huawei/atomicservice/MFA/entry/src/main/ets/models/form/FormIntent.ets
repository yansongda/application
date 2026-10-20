// 卡片意图（主应用侧）：EntryAbility 解析 postCardAction(router) 的 want 参数后写入，
// Index 页通过 @Monitor('formIntent.version') 感知并消费。
// 路由定义见 FormRoute：FormRoute.SCAN = 直达扫码添加；FormRoute.INPUT = 直达手动输入添加页。
// 未登录 / 应用锁锁定 / 页面未激活时由 Index 暂缓消费，超过 TTL 后丢弃。
// 注意：postCardAction 的 params 被整体包装为 want.parameters.params（JSON 字符串），不逐键平铺；
// 日志不得出现 token / 密钥 / 验证码。
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../../App';
import { State } from '../Auth';
import { FORM_ROUTE_PARAM, FormRoute, parseFormRoute } from './FormRoute';

// 待处理卡片意图的保质期：解锁/登录等待超过该时长后不再消费，避免陈旧意图突然触发
export const FORM_INTENT_TTL_MS: number = 5 * 60 * 1000;

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

  // 返回仍可消费的路由：无意图 / 已过期 → undefined；过期时顺手清空。
  // 不判断登录、应用锁、页面激活态，这些由调用方决定。
  pendingRoute(now: number = Date.now()): FormRoute | undefined {
    const route: FormRoute | undefined = this.route;

    if ('undefined' === typeof route || !(this.version > 0)) {
      return undefined;
    }

    if (now - this.createdAt > FORM_INTENT_TTL_MS) {
      this.route = undefined;
      hilog.info(LogDomain.MODELS, 'models/form/FormIntent', '卡片意图已过期: route=%{public}s', route);

      return undefined;
    }

    return route;
  }

  // 消费成功（或主动放弃）后清空；version 保留，不影响 @Monitor 语义
  clear(): void {
    this.route = undefined;
  }

  // 纯策略：页面激活 + 未锁定 + 已登录；状态判断收敛在模型内
  static canConsume(active: boolean, locked: boolean, state: State): boolean {
    return active && !locked && State.NORMAL === state;
  }

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
