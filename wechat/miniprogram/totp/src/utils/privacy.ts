import logger from "./logger";
import { markDirty, readSettings, writeSettings } from "./security";

// 防截屏/录屏的唯一写入口：wx.setVisualEffectOnCapture。
// 本地设置（privacyWindow，默认 true = fail-closed）是唯一真相源：
// applyCurrent 冷启动/回前台按存储值落地；applyRemote 从服务端恢复用户意愿（不置 dirty）。
const isSupported = (): boolean => {
  // canIUse + typeof 双守卫（基础库 2.20.1+；iOS 需 3.3.0+ 且 iOS16+，且 iOS 只影响录屏）
  return (
    typeof wx.canIUse === "function" &&
    wx.canIUse("setVisualEffectOnCapture") &&
    typeof wx.setVisualEffectOnCapture === "function"
  );
};

const apply = (on: boolean): void => {
  wx.setVisualEffectOnCapture({
    visualEffect: on ? "hidden" : "none",
    fail: (err) => {
      logger.warning("防截屏设置失败", err.errMsg);
    },
  });
};

const applyCurrent = (): void => {
  apply(readSettings().privacyWindow);
};

const setEnabled = (on: boolean): boolean => {
  if (on && !isSupported()) {
    return false;
  }

  // 先落盘、成功才落地系统——失败返回 false 且内存不变（调用方提示用户）
  if (!writeSettings({ ...readSettings(), privacyWindow: on })) {
    return false;
  }

  markDirty();
  apply(on);

  return true;
};

// 服务端恢复：与本地相同则不动（避免无谓写盘）；不置 dirty——远端值再上行没有意义。
// on=false 无需能力守卫，直接落地（与 AppLock.applyRemote 的凭据守卫形成对比）。
const applyRemote = (on: boolean): void => {
  if (
    readSettings().privacyWindow !== on &&
    !writeSettings({ ...readSettings(), privacyWindow: on })
  ) {
    logger.warning("防截屏远端恢复写盘失败");
  }

  apply(on);
};

export { apply, applyCurrent, applyRemote, isSupported, setEnabled };
