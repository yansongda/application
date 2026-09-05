import { computeCode } from "@utils/totp";
import { readCache } from "@utils/totp-cache";

Component({
  properties: {
    // 这里和组件的 id 冲突，所以改为 itemId
    itemId: String,
    username: String,
    issuer: String,
    secret: String,
    period: {
      type: Number,
      value: 30,
    },
  },

  data: {
    code: "",
    remainSeconds: 0,
    refreshCodeTimeoutIdentity: -1,
    countdownIntervalIdentity: -1,
  },

  lifetimes: {
    attached() {
      this.computeCode();
      this.countdownRefresh();
    },
    detached() {
      this.clear();
    },
  },

  pageLifetimes: {
    show() {
      this.computeCode();
      this.countdownRefresh();
    },
    hide() {
      this.clear();
    },
  },

  methods: {
    computeCode() {
      const secret = this.data.secret;

      if (!secret) {
        this.setData({ code: "------" });
        this.triggerEvent("message", "验证码计算失败");

        return;
      }

      try {
        const offset = readCache()?.clock_offset ?? 0;

        this.setData({
          code: computeCode(secret, this.data.period, Date.now() + offset),
        });
      } catch (_e: unknown) {
        this.setData({ code: "------" });
        this.triggerEvent("message", "验证码计算失败");
      }
    },
    countdownRefresh() {
      this.clear();

      const period = this.data.period ?? 30;
      const now = new Date();
      const remainSeconds = period - (now.getSeconds() % period);

      this.data.refreshCodeTimeoutIdentity = setTimeout(() => {
        this.computeCode();
        this.countdownRefresh();
      }, remainSeconds * 1000);

      let countdown = remainSeconds;
      this.setData({ remainSeconds: countdown });
      this.data.countdownIntervalIdentity = setInterval(() => {
        countdown--;
        if (countdown <= 0) {
          clearInterval(this.data.countdownIntervalIdentity);
        }
        this.setData({ remainSeconds: countdown });
      }, 1000);
    },
    detail() {
      this.triggerEvent("detail", this.data.itemId);
    },
    delete() {
      this.triggerEvent("delete", this.data.itemId);
    },
    clear() {
      clearTimeout(this.data.refreshCodeTimeoutIdentity);
      this.data.refreshCodeTimeoutIdentity = -1;

      clearInterval(this.data.countdownIntervalIdentity);
      this.data.countdownIntervalIdentity = -1;
    },
  },
});
