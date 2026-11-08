import { syncOnPageShow as appLockSyncOnPageShow } from "@utils/app-lock";

Page({
  data: {
    locked: false,
    sections: [
      {
        icon: "scan",
        title: "添加账号",
        items: [
          "扫描服务商提供的二维码，即可自动添加",
          "也可手动输入发行方、用户名与密钥创建",
        ],
      },
      {
        icon: "copy",
        title: "验证码与复制",
        items: ["在列表中点击验证码，即可快速复制到剪贴板"],
      },
      {
        icon: "refresh",
        title: "多设备同步",
        items: ["登录同一账号后，账号列表会在你的设备间同步"],
      },
      {
        icon: "search",
        title: "搜索 / 标签 / 置顶",
        items: [
          "在首页搜索发行方、用户名或标签，快速定位账号",
          "在详情页设置标签；标签会同步到账号，并显示在列表项右上角",
          "左滑或详情页可置顶；置顶账号排在最前，分组视图按置顶、标签、未分类排列",
        ],
      },
      {
        icon: "file",
        title: "加密备份",
        items: [
          "「我的 → 导入 / 导出」可把账号导出为口令加密的 .mfa 文件；文件与剪贴板中只有密文",
          "口令不会被保存：忘记口令将无法恢复，也不提供重置或找回",
          "华为元服务与微信小程序的备份可互相导入（同一口令），标签与置顶会一并保留",
          "剪贴板通道导入完成后，请及时清理剪贴板；备份文件也请勿长期留在聊天记录中",
        ],
      },
      {
        icon: "lock-on",
        title: "安全说明",
        items: [
          "验证码在你本机离线计算，密钥不会离开设备",
          "在列表项上左滑可删除该账号",
          "删除账号后该条目对应的数据将一并删除，且无法恢复",
        ],
      },
    ],
  },
  onShow() {
    // 应用锁守卫：锁定时直接渲染遮罩（页面无取数/计时）
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
});
