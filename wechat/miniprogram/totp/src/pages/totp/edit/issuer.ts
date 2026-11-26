import api from "@api/totp";
import { submitEditField } from "@utils/edit-field";
import { guardOnShow, guardOnUnlocked } from "@utils/page-guard";
import { updateItemFields } from "@utils/totp-cache";
import type { EditIssuerRequest } from "types/totp";
import type { FormSubmit } from "types/wechat";

interface Query {
  id?: string;
  issuer?: string;
}

interface FormData {
  issuer: string;
}

Page({
  data: {
    locked: false,
    id: "0",
    issuer: "",
  },
  onShow() {
    // 应用锁守卫：锁定时不发请求，直接渲染遮罩
    guardOnShow(this);
  },
  // 解锁成功：页面无取数/计时，仅解除锁定
  onUnlocked() {
    guardOnUnlocked(this);
  },
  onLoad(query: Query) {
    this.setData({
      id: query.id || "0",
      issuer: query.issuer ? decodeURIComponent(query.issuer) : "",
    });
  },
  async submit(e: FormSubmit<FormData>) {
    await submitEditField({
      host: this,
      id: this.data.id,
      value: e.detail.value.issuer.trim(),
      emptyMessage: "提供商名称不能为空",
      submit: (id, issuer) =>
        api.editIssuer({ id, issuer } as EditIssuerRequest),
      onSaved: (issuer) => updateItemFields(this.data.id, { issuer }),
    });
  },
  async cancel() {
    await wx.navigateBack();
  },
});
