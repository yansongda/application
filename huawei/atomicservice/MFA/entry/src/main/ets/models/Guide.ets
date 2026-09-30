// 引导页展示状态（持久化模型）：与页面 UI 解耦，页面只负责「何时展示」
@ObservedV2
export class IndexGuideState {
  // 引导页是否已不再展示（持久化）：点过「跳过/开始使用」，或已自动展示过一次
  @Trace isSkipped: boolean = false;
}
