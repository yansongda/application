import api from "@api/totp";
import { HttpError } from "@models/error";
import { syncOnPageShow as appLockSyncOnPageShow } from "@utils/app-lock";
import { upsertItem } from "@utils/totp-cache";
import { buildTotpUri, describeOtpError } from "@utils/totp-uri";
import Message from "tdesign-miniprogram/message/index";
import Toast from "tdesign-miniprogram/toast/index";
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
    const locked = appLockSyncOnPageShow();

    if (locked !== this.data.locked) {
      this.setData({ locked });
    }

    if (locked) {
      return;
    }
  },
  // 解锁成功：页面无取数/计时，仅解除锁定
  onUnlocked() {
    this.setData({ locked: false });
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

    if (secret.length === 0) {
      Toast({
        message: "请填写密钥",
        theme: "error",
        duration: 1500,
        direction: "column",
      });

      return;
    }

    if (!Number.isInteger(period) || period <= 0) {
      Toast({
        message: "周期需为正整数",
        theme: "error",
        duration: 1500,
        direction: "column",
      });

      return;
    }

    if (digits < 6 || digits > 8) {
      Toast({
        message: "位数需在 6 至 8 之间",
        theme: "error",
        duration: 1500,
        direction: "column",
      });

      return;
    }

    this.submitting = true;

    Toast({
      message: "创建中...",
      theme: "loading",
      duration: 5000,
      direction: "column",
      preventScrollThrough: true,
    });

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
      const item = await api.create(uri);

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

      Toast({
        message: "创建成功",
        theme: "success",
        duration: 1500,
        direction: "column",
        preventScrollThrough: true,
      });

      setTimeout(() => wx.navigateBack(), 1500);
    } catch (err: unknown) {
      this.submitting = false;

      Toast({
        message: "创建失败",
        theme: "error",
        duration: 100,
        direction: "column",
      });

      // buildTotpUri 抛 OtpError → describeOtpError；api.create 抛 HttpError（后端错误）。
      Message.error({
        content: `创建失败：${err instanceof HttpError ? err.message : describeOtpError(err)}`,
        duration: 5000,
        offset: [20, 32],
        context: this,
      });
    }
  },
  async cancel() {
    await wx.navigateBack();
  },
});
