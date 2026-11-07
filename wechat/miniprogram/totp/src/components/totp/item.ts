import { copyText } from "@utils/clipboard";
import { computeSnapshot } from "@utils/totp";

Component({
  properties: {
    // 这里和组件的 id 冲突，所以改为 itemId
    itemId: String,
    username: String,
    issuer: String,
    secret: String,
    // 标签与置顶状态：由页面从缓存透传（后端 config.tags / config.pinned 投影）
    tags: {
      type: Array,
      value: [],
    },
    pinned: {
      type: Boolean,
      value: false,
    },
    period: {
      type: Number,
      value: 30,
    },
    digits: {
      type: Number,
      value: 6,
    },
    algorithm: {
      type: String,
      value: "SHA1",
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
        // 一次构建实例同时拿到验证码与剩余秒数，进度条按 remaining / period 计算
        const snapshot = computeSnapshot(
          secret,
          this.data.period,
          this.data.digits,
          this.data.algorithm,
          Date.now(),
        );

        this.setData({
          code: snapshot.code,
          remainSeconds: snapshot.remaining,
        });
      } catch (_e: unknown) {
        this.setData({ code: "------" });
        this.triggerEvent("message", "验证码计算失败");
      }
    },
    countdownRefresh() {
      this.clear();

      const period = this.data.period ?? 30;
      // 以 epoch 秒取模对齐周期边界，保证「倒计时归零」与「验证码翻转」在同一
      // 时刻发生；对任意时区与任意周期均成立。
      const alignedSeconds = Math.floor(Date.now() / 1000);
      const remainSeconds = period - (alignedSeconds % period);

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
    // 卡片主体点击 → 详情页（验证码区域 catchtap 复制，不会触发本事件）
    detail() {
      this.triggerEvent("detail", this.data.itemId);
    },
    // 左滑删除
    delete() {
      this.triggerEvent("delete", this.data.itemId);
    },
    // 左滑置顶/取消置顶：事件携带目标值（页面按此值请求服务端并更新缓存，
    // 避免页面在组件内查询当前 pinned 的时序问题）
    pin() {
      this.triggerEvent("pin", {
        id: this.data.itemId,
        pinned: !this.data.pinned,
      });
    },
    // 验证码即复制入口：点击右侧验证码区域直接复制
    async copy() {
      const code = this.data.code;

      if (!code || code === "------") {
        return;
      }

      const ok = await copyText(code);

      if (!ok) {
        wx.showToast({ title: "复制失败", icon: "none" });
      }
    },
    clear() {
      clearTimeout(this.data.refreshCodeTimeoutIdentity);
      this.data.refreshCodeTimeoutIdentity = -1;

      clearInterval(this.data.countdownIntervalIdentity);
      this.data.countdownIntervalIdentity = -1;
    },
  },
});
