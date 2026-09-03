const l = wx.getRealtimeLogManager ? wx.getRealtimeLogManager() : null;

const logger = {
  // biome-ignore lint: 日志
  info: (...args: any[]) => {
    l?.info(...args);
  },
  // biome-ignore lint: 日志
  warning: (...args: any[]) => {
    l?.warn(...args);
  },
  // biome-ignore lint: 日志
  error: (...args: any[]) => {
    l?.error(...args);
  },
};

export default logger;
