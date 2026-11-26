// 资源 → 字符串的唯一入口。
//
// `ResourceManager.getStringSync` 会**同步抛**（资源 id 不存在、进程未就绪、非 UI 上下文缺 context），
// 而调用方基本只关心「拿到文案、拿不到就用兜底」。这段 try/catch 曾在 Http / AppLock / EditText / Detail
// 各写一份，且兜底策略各不相同（有的返回空串、有的沿用上一次的值）——集中到这里后，
// 调用方只需显式给出兜底值，`utils/Http.ets` 也不再需要 import `application`。
import { application, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogDomain } from '../App';

// context 可选：UI 页面内可传 `getUIContext().getHostContext()`（与页面同源）；
// 不传则走应用级 ResourceManager（非 UI 场景足够）
export function stringOf(resource: Resource, fallback: string = '', context?: common.Context): string {
  try {
    const manager = 'undefined' === typeof context
      ? application.getApplicationContext().resourceManager
      : context.resourceManager;

    return manager.getStringSync(resource.id);
  } catch (e) {
    hilog.warn(LogDomain.UTILS, 'utils/resource', '读取资源文案失败，使用兜底: resource=%{public}d, err=%{public}s',
      resource.id, JSON.stringify(e));

    return fallback;
  }
}
