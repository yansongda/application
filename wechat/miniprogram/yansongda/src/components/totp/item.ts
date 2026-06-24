import api from "@api/totp";
import type { HttpError } from "@models/error";

Component({
  properties: {
    // 这里和组件的 id 冲突，所以改为 itemId
    itemId: String,
    username: String,
    issuer: String,
    code: String,
    period: Number,
  },

  data: {
    remainSeconds: 0,
    refreshCodeTimeoutIdentity: -1,
    countdownIntervalIdentity: -1,
  },

  lifetimes: {
    attached() {
      this.countdownRefresh();
    },
    detached() {
      this.clear();
    },
  },

  pageLifetimes: {
    show() {
      this.countdownRefresh();
    },
    hide() {
      this.clear();
    },
  },

  methods: {
    countdownRefresh() {
      this.clear();

      const period = this.data.period ?? 30;
      const now = new Date();
      const remainSeconds = period - (now.getSeconds() % period);

      this.data.refreshCodeTimeoutIdentity = setTimeout(() => {
        this.refreshCode(this.data.itemId);
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
    refreshCode(id: string) {
      api
        .detail(id)
        .then((response) => this.setData({ code: response.code }))
        .catch((e: HttpError) =>
          this.triggerEvent("message", `更新验证码失败：${e.message}`),
        );
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
