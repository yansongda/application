import api from "@api/totp";
import { withLoading } from "@utils/loading";
import { notify, toast } from "@utils/notify";
import { guardOnShow, guardOnUnlocked } from "@utils/page-guard";
import { upsertItem } from "@utils/totp-cache";
import { buildTotpUri, describeOtpError } from "@utils/totp-uri";
import type { TotpAlgorithm } from "types/totp";
import type { FormSubmit } from "types/wechat";

interface FormData {
  issuer: string;
  account: string;
  period: string;
  secret: string;
}

interface ChangeEvent {
  detail: {
    value: string;
  };
}

interface PickerConfirm {
  detail: {
    value: (string | number)[];
  };
}

Page({
  data: {
    locked: false,
    issuer: "",
    account: "",
    period: "30",
    digits: 6,
    algorithm: "SHA1" as TotpAlgorithm,
    secret: "",
    digitsOptions: [
      { label: "6 位", value: 6 },
      { label: "7 位", value: 7 },
      { label: "8 位", value: 8 },
    ],
    algorithmOptions: [
      { label: "SHA1", value: "SHA1" },
      { label: "SHA256", value: "SHA256" },
      { label: "SHA512", value: "SHA512" },
    ],
    digitsValue: [6],
    algorithmValue: ["SHA1"],
    digitsVisible: false,
    algorithmVisible: false,
  },
  submitting: false,
  onShow() {
    // 应用锁守卫：锁定时不发请求，直接渲染遮罩
    guardOnShow(this);
  },
  // 解锁成功：页面无取数/计时，仅解除锁定
  onUnlocked() {
    guardOnUnlocked(this);
  },
  onIssuerChange(e: ChangeEvent) {
    this.setData({ issuer: e.detail.value });
  },
  onAccountChange(e: ChangeEvent) {
    this.setData({ account: e.detail.value });
  },
  onPeriodChange(e: ChangeEvent) {
    this.setData({ period: e.detail.value });
  },
  onSecretChange(e: ChangeEvent) {
    // 转大写并过滤非 Base32 字符（A-Z、2-7）；setData 回写让用户看到过滤结果。
    const value = e.detail.value.toUpperCase().replace(/[^A-Z2-7]/g, "");

    this.setData({ secret: value });
  },
  openDigitsPicker() {
    this.setData({ digitsVisible: true, algorithmVisible: false });
  },
  openAlgorithmPicker() {
    this.setData({ digitsVisible: false, algorithmVisible: true });
  },
  onDigitsConfirm(e: PickerConfirm) {
    const value = Number(e.detail.value[0]);

    this.setData({ digits: value, digitsValue: [value], digitsVisible: false });
  },
  onAlgorithmConfirm(e: PickerConfirm) {
    const value = String(e.detail.value[0]) as TotpAlgorithm;

    this.setData({
      algorithm: value,
      algorithmValue: [value],
      algorithmVisible: false,
    });
  },
  onPickerCancel() {
    this.setData({ digitsVisible: false, algorithmVisible: false });
  },
  async submit(e: FormSubmit<FormData>) {
    if (this.submitting) {
      return;
    }

    const issuer = e.detail.value.issuer.trim();
    const account = e.detail.value.account.trim();
    const secret = e.detail.value.secret.trim();
    const period = Number(e.detail.value.period);
    const digits = this.data.digits;

    // @yansongda/miniprogram-otp v2 起 otpauth label 必须有「非空且不含冒号」的 account：
    // 空值 / 含冒号会抛 INVALID_OTPAUTH_URI（该文案面向扫码场景，手动创建时误导），故前置拦截。
    if (account.length === 0) {
      toast.error("请填写用户名", 1500);

      return;
    }

    if (account.includes(":")) {
      toast.error("用户名不能包含冒号", 1500);

      return;
    }

    if (secret.length === 0) {
      toast.error("请填写密钥", 1500);

      return;
    }

    if (!Number.isInteger(period) || period <= 0) {
      toast.error("周期需为正整数", 1500);

      return;
    }

    this.submitting = true;

    try {
      // strict 校验 Base32（GGG / MZXW6YT 等非规范密钥在此被拒），
      // 与后端 from_url_unchecked 的宽松解码行为对齐前先本地拦截。
      const uri = buildTotpUri({
        issuer,
        account,
        secret,
        period,
        digits,
        algorithm: this.data.algorithm,
      });
      const item = await withLoading("创建中...", () => api.create(uri));

      // 直接用 create 响应（服务端入库值）写缓存，避免前端二次解析 URI。
      upsertItem({
        id: item.id,
        issuer: item.issuer,
        username: item.username,
        secret: item.config.secret,
        period: item.config.period,
        digits: item.config.digits,
        algorithm: item.config.algorithm,
        tags: item.tags ?? [],
        pinned: item.pinned === true,
      });

      toast.success("创建成功", 1500);

      setTimeout(() => wx.navigateBack(), 1500);
    } catch (err: unknown) {
      this.submitting = false;

      // buildTotpUri 抛 OtpError；api.create 抛 HttpError —— 文案统一由 describeOtpError 处理
      notify.error(this, `创建失败：${describeOtpError(err)}`);
    }
  },
  async cancel() {
    await wx.navigateBack();
  },
});
