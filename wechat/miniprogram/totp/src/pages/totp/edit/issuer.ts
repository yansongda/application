import api from "@api/totp";
import error from "@utils/error";
import { withLoading } from "@utils/loading";
import { notify, toast } from "@utils/notify";
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
    const issuer = e.detail.value.issuer.trim();

    // 空值不提交：提示后返回，不发请求。
    if (issuer.length === 0) {
      toast.error("提供商名称不能为空", 1500);

      return;
    }

    try {
      await withLoading("更新中...", () =>
        api.editIssuer({
          id: this.data.id,
          issuer,
        } as EditIssuerRequest),
      );

      updateItemFields(this.data.id, { issuer });

      toast.success("修改成功", 1500);

      setTimeout(() => wx.navigateBack(), 1500);
    } catch (e: unknown) {
      notify.error(this, `更新失败：${error.getErrorMessage(e)}`);
    }
  },
  async cancel() {
    await wx.navigateBack();
  },
});
