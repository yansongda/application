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
    slogan: "",
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
    this.setData({ slogan: readUserCache()?.config.slogan ?? "" });
  },
  onInput(e: InputEvent) {
    this.setData({ slogan: e.detail.value });
  },
  async onSave() {
    const slogan = this.data.slogan.trim();

    if (slogan.length <= 3) {
      notify.error(this, "Slogan 至少 4 个字符");

      return;
    }

    if (slogan.length > 128) {
      notify.error(this, "Slogan 最多 128 个字符");

      return;
    }

    if (this.saving) {
      return;
    }

    this.saving = true;

    try {
      await withLoading("保存中...", () => userApi.editSlogan(slogan));
    } catch (e) {
      this.saving = false;
      notify.error(this, `保存失败：${error.getErrorMessage(e)}`);

      return;
    }

    updateUserCache({ config: { slogan } });

    toast.success("Slogan 已更新", 1500);

    await wx.navigateBack();
  },
});
