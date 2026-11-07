import Toast, { hideToast } from "tdesign-miniprogram/toast/index";

// 让 loading 先进入视图层再发请求：setData 是异步的，若接口在本地/开发环境
// 快速返回，loading 可能在渲染前就被结果 Toast 顶掉，看起来像「请求前没 loading」。
const nextPaint = (): Promise<void> =>
  new Promise((resolve) => {
    wx.nextTick(() => resolve());
  });

// 接口调用统一入口：先出「处理中」类 loading，再执行 task，无论成功失败都收起。
// duration 取 0（不自动消失），统一由 finally 关闭；http 层有 5s timeout 兜底。
const withLoading = async <T>(
  message: string,
  task: () => Promise<T>,
): Promise<T> => {
  Toast({
    message,
    theme: "loading",
    duration: 0,
    direction: "column",
    preventScrollThrough: true,
  });

  await nextPaint();

  try {
    return await task();
  } finally {
    hideToast();
  }
};

export { withLoading };
