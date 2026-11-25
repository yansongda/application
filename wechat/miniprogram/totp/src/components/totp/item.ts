import { copyText } from "@utils/clipboard";
import { onSecond } from "@utils/ticker";
import { computeSnapshot } from "@utils/totp";

// 每实例的 ticker 状态。组件 options 不接受自定义实例属性
// （miniprogram-api-typings 的 Options 只涵盖 data/properties/methods/lifetimes/…），
// 因此用 WeakMap 挂在实例上：随实例回收，不进 data（函数不能进 data）。
interface TickState {
  off: () => void;
  failed: boolean;
}

const tickStates = new WeakMap<object, TickState>();

const stateOf = (host: object): TickState => {
  const existing = tickStates.get(host);

  if (existing !== undefined) {
    return existing;
  }

  const created: TickState = { off: () => undefined, failed: false };

  tickStates.set(host, created);

  return created;
};

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
  },

  lifetimes: {
    attached() {
      this.start();
    },
    detached() {
      this.stop();
      tickStates.delete(this);
    },
  },

  pageLifetimes: {
    show() {
      this.start();
    },
    hide() {
      this.stop();
    },
  },

  methods: {
    // 订阅全局整秒 ticker：N 张卡片共用一个定时器。
    // 原实现每张卡片各自 setTimeout + setInterval，且倒计时靠本地递减，会随负载漂移。
    start() {
      this.stop();
      this.tick();

      const state = stateOf(this);

      state.off = onSecond(() => this.tick());
    },
    stop() {
      const state = tickStates.get(this);

      if (state === undefined) {
        return;
      }

      state.off();
      state.off = () => undefined;
    },
    tick() {
      const secret = this.data.secret;

      if (!secret) {
        this.fail();

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

        stateOf(this).failed = false;
        this.setData({
          code: snapshot.code,
          remainSeconds: snapshot.remaining,
        });
      } catch (_e: unknown) {
        this.fail();
      }
    },
    // 算码失败只在首次提示：ticker 每秒回调，不去重会变成每秒弹一次
    fail() {
      const state = stateOf(this);

      if (this.data.code !== "------") {
        this.setData({ code: "------" });
      }

      if (!state.failed) {
        state.failed = true;
        this.triggerEvent("message", "验证码计算失败");
      }
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
  },
});
