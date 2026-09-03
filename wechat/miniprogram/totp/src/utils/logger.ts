const l = wx.getRealtimeLogManager ? wx.getRealtimeLogManager() : null;

const logger = {
  // biome-ignore lint: 微信日志 API 签名要求 any
  info: (...args: any[]) => {
    l?.info(...args);
  },
  // biome-ignore lint: 微信日志 API 签名要求 any
  warning: (...args: any[]) => {
    l?.warn(...args);
  },
  // biome-ignore lint: 微信日志 API 签名要求 any
  error: (...args: any[]) => {
    l?.error(...args);
  },
};

export default logger;
