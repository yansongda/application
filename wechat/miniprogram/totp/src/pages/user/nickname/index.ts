import userApi from "@api/user";
import error from "@utils/error";
import { withLoading } from "@utils/loading";
import { notify, toast } from "@utils/notify";
import { guardOnShow, guardOnUnlocked } from "@utils/page-guard";
import { readUserCache, updateUserCache } from "@utils/user-cache";

interface InputEvent {
  detail: { value: string };
}

Page({
  data: {
    locked: false,
    nickname: "",
  },
  saving: false,
  onShow() {
    // 应用锁守卫：锁定时不发请求，直接渲染遮罩
    guardOnShow(this);
  },
  // 解锁成功：页面无取数/计时，仅解除锁定
  onUnlocked() {
    guardOnUnlocked(this);
  },
  onLoad() {
    this.setData({ nickname: readUserCache()?.config.nickname ?? "" });
  },
  onInput(e: InputEvent) {
    this.setData({ nickname: e.detail.value });
  },
  async onSave() {
    const nickname = this.data.nickname.trim();

    if (nickname.length === 0) {
      notify.error(this, "昵称不能为空");

      return;
    }

    if (nickname.length > 16) {
      notify.error(this, "昵称最多 16 个字符");

      return;
    }

    if (this.saving) {
      return;
    }

    this.saving = true;

    try {
      await withLoading("保存中...", () => userApi.editNickname(nickname));
    } catch (e) {
      this.saving = false;
      notify.error(this, `保存失败：${error.getErrorMessage(e)}`);

      return;
    }

    updateUserCache({ config: { nickname } });

    toast.success("昵称已更新", 1500);

    await wx.navigateBack();
  },
});
