import api from "@api/totp";
import error from "@utils/error";
import { withLoading } from "@utils/loading";
import { notify, toast } from "@utils/notify";
import { guardOnShow, guardOnUnlocked } from "@utils/page-guard";
import { updateItemFields } from "@utils/totp-cache";
import type { EditUsernameRequest } from "types/totp";
import type { FormSubmit } from "types/wechat";

interface Query {
  id?: string;
  username?: string;
}

interface FormData {
  username: string;
}

Page({
  data: {
    locked: false,
    id: "0",
    username: "",
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
      username: query.username ? decodeURIComponent(query.username) : "",
    });
  },
  async submit(e: FormSubmit<FormData>) {
    const username = e.detail.value.username.trim();

    // 空值不提交：提示后返回，不发请求。
    if (username.length === 0) {
      toast.error("账号名称不能为空", 1500);

      return;
    }

    try {
      await withLoading("更新中...", () =>
        api.editUsername({
          id: this.data.id,
          username,
        } as EditUsernameRequest),
      );

      updateItemFields(this.data.id, { username });

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
