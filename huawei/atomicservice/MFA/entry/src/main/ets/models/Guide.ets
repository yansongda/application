import { PersistenceV2 } from '@kit.ArkUI';

// 空态引导展示状态（持久化模型）：与页面 UI 解耦 —— 模型负责「是否还应展示」与持久化标记，
// 页面只负责本次进入的内存态可见性（isGuideVisible）。
@ObservedV2
export class IndexGuideState {
  // 是否已不再展示引导（持久化）：已自动展示过一次，或用户点过「不再提示」
  @Trace isSkipped: boolean = false;

  // 是否应展示引导卡：有账号或已跳过时不展示
  canShow(count: number): boolean {
    return count <= 0 && !this.isSkipped;
  }

  // 首次展示即写入「不再展示」标记：保证之后数据仍为空也不再展示
  markShown(): void {
    this.isSkipped = true;
    PersistenceV2.save(IndexGuideState);
  }
}
