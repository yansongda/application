// 首页刷新决策的单测：覆盖「静默 / 交互式」两条入口与「在飞任务类型」交叉的四条组合，
// 外加「补一次之后状态复位」与「refreshFlight 复位后重新 START」两条边界。
// 这三态原本写在 `pages/index/Index.ets` 里、只有注释没有用例，是静默刷新最容易回归的地方。
import { describe, expect, it } from '@ohos/hypium';
import { RefreshPlan, RefreshPlanner } from '../main/ets/models/index/RefreshPlanner';

export default function refreshPlannerTest(): void {
  describe('refreshPlanner', () => {
    it('idle_starts', 0, () => {
      const planner: RefreshPlanner = new RefreshPlanner();

      expect(planner.plan(false, false)).assertEqual(RefreshPlan.START);
      expect(planner.plan(false, true)).assertEqual(RefreshPlan.START);
    });

    it('silent_while_silent_shares', 0, () => {
      const planner: RefreshPlanner = new RefreshPlanner();

      expect(planner.plan(false, true)).assertEqual(RefreshPlan.START);
      // 两次静默刷新叠加（onActive 连续触发）：共享在飞任务，不重复请求
      expect(planner.plan(true, true)).assertEqual(RefreshPlan.SHARE);
      expect(planner.plan(true, true)).assertEqual(RefreshPlan.SHARE);
    });

    it('silent_while_interactive_shares', 0, () => {
      const planner: RefreshPlanner = new RefreshPlanner();

      expect(planner.plan(false, false)).assertEqual(RefreshPlan.START);
      // 在飞的已经是交互式：静默调用直接等它即可
      expect(planner.plan(true, true)).assertEqual(RefreshPlan.SHARE);
    });

    it('interactive_while_interactive_shares', 0, () => {
      const planner: RefreshPlanner = new RefreshPlanner();

      expect(planner.plan(false, false)).assertEqual(RefreshPlan.START);
      expect(planner.plan(true, false)).assertEqual(RefreshPlan.SHARE);
    });

    it('interactive_while_silent_enqueues_once', 0, () => {
      const planner: RefreshPlanner = new RefreshPlanner();

      expect(planner.plan(false, true)).assertEqual(RefreshPlan.START);
      // 下拉刷新 / 重试按钮撞上在飞的静默刷新：补一次带 loading 的刷新
      expect(planner.plan(true, false)).assertEqual(RefreshPlan.ENQUEUE);
      // 补发已经登记，后续的交互式调用只需等它，不再重复排队
      expect(planner.plan(true, false)).assertEqual(RefreshPlan.SHARE);
      expect(planner.plan(true, true)).assertEqual(RefreshPlan.SHARE);
    });

    it('enqueue_resets_after_settle', 0, () => {
      const planner: RefreshPlanner = new RefreshPlanner();

      expect(planner.plan(false, true)).assertEqual(RefreshPlan.START);
      expect(planner.plan(true, false)).assertEqual(RefreshPlan.ENQUEUE);
      // 队列清空后再来一次：重新从 START 开始，并重新记录本次的 silent
      expect(planner.plan(false, false)).assertEqual(RefreshPlan.START);
      expect(planner.plan(true, true)).assertEqual(RefreshPlan.SHARE);
    });
  });
}
