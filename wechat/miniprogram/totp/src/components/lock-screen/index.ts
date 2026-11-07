import { unlock, VerifyOutcome, verify } from "@utils/app-lock";
import Toast from "tdesign-miniprogram/toast/index";

// 锁屏遮罩：由页面在 locked 时条件渲染，不占路由、不碰导航栈。
// attached 自动发起身份验证；组件内不得直接调用 wx.startSoterAuthentication
// （统一走 AppLock.verify，见技术设计 §3.5.3）。
Component({
  data: {
    hint: "",
  },

  lifetimes: {
    attached() {
      this.trigger();
    },
  },

  methods: {
    // 事件拦截：catchtouchmove/catchtap 阻止底层页面滚动与点击穿透
    noop() {
      return;
    },
    async trigger() {
      const outcome = await verify();

      switch (outcome) {
        case VerifyOutcome.SUCCESS:
          // verify 成功不会在内部解锁：必须先显式 unlock，再通知页面卸载遮罩
          unlock();
          this.triggerEvent("unlocked");
          break;
        case VerifyOutcome.NO_CREDENTIAL:
          // 设备无凭据：AppLock 已在内部本地关闭应用锁并解锁（防锁死降级）
          Toast({
            message: "设备未录入指纹或面容，已关闭应用锁",
            duration: 3000,
            context: this,
          });
          this.triggerEvent("unlocked");
          break;
        case VerifyOutcome.FAILED:
          this.setData({ hint: "验证失败，请重试" });
          break;
        case VerifyOutcome.CANCELED:
          this.setData({ hint: "已取消验证" });
          break;
        case VerifyOutcome.SKIPPED:
          // 命中 3 秒防抖 / 已在验证中：不改提示，由用户稍后手动重试
          break;
      }
    },
  },
});
