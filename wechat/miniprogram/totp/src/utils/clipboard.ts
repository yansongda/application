import logger from "./logger";

// 复制文本到剪贴板：成功返回 true 并 toast（文案与华为端一致）；失败返回 false。
// wx.setClipboardData 自带系统 toast“内容已复制”，此处再提示品牌文案以对齐华为端交互。
// 禁止把 text（验证码 / 密钥明文）写进任何日志。
const copyText = async (
  text: string,
  message = "验证码已复制",
): Promise<boolean> => {
  try {
    await wx.setClipboardData({ data: text });

    wx.showToast({ title: message, icon: "none" });

    return true;
  } catch (e: unknown) {
    logger.warning("复制到剪贴板失败", e);

    return false;
  }
};

// 读取剪贴板文本（仅备份导入使用）。内容同样禁止进入日志：失败只记录事件。
const readText = async (): Promise<string | undefined> => {
  try {
    const result = await wx.getClipboardData();

    return typeof result.data === "string" ? result.data : undefined;
  } catch (e: unknown) {
    logger.warning("读取剪贴板失败", e);

    return undefined;
  }
};

export { copyText, readText };
