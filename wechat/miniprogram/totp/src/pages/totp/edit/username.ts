import api from "@api/totp";
import { submitEditField } from "@utils/edit-field";
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
    await submitEditField({
      host: this,
      id: this.data.id,
      value: e.detail.value.username.trim(),
      emptyMessage: "账号名称不能为空",
      submit: (id, username) =>
        api.editUsername({ id, username } as EditUsernameRequest),
      onSaved: (username) => updateItemFields(this.data.id, { username }),
    });
  },
  async cancel() {
    await wx.navigateBack();
  },
});
