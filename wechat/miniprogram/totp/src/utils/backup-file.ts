/**
 * 备份文件通道（微信侧唯一 wx 文件 / 随机数入口）：
 * - 导出：写 USER_DATA_PATH 后由用户点击转发（wx.shareFileMessage 必须用户触发）
 * - 导入：从聊天选择文件并读文本（wx.chooseMessageFile，不依赖后缀）
 * 本模块不做加解密、不打日志内容。
 */
import logger from "./logger";

export interface BackupFile {
  filePath: string;
  fileName: string;
}

const pad = (value: number): string => {
  return value.toString().padStart(2, "0");
};

/** 推荐命名 mfa-backup-YYYYMMDD-HHmm.mfa（规范 §7）。 */
export const buildBackupFileName = (now: Date = new Date()): string => {
  const date = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}`;
  const time = `${pad(now.getHours())}${pad(now.getMinutes())}`;

  return `mfa-backup-${date}-${time}.mfa`;
};

export const writeBackupFile = (text: string, fileName: string): BackupFile => {
  const filePath = `${wx.env.USER_DATA_PATH}/${fileName}`;

  wx.getFileSystemManager().writeFileSync(filePath, text, "utf8");

  return { filePath, fileName };
};

/** 必须由用户点击回调触发（官方限制），失败向上抛。 */
export const shareBackupFile = async (file: BackupFile): Promise<void> => {
  await wx.shareFileMessage({
    filePath: file.filePath,
    fileName: file.fileName,
  });
};

const readFileText = (filePath: string): Promise<string> => {
  return new Promise((resolve, reject) => {
    wx.getFileSystemManager().readFile({
      filePath,
      encoding: "utf8",
      success: (res) => {
        resolve(typeof res.data === "string" ? res.data : "");
      },
      fail: (err) => {
        reject(new Error(err.errMsg || "readFile failed"));
      },
    });
  });
};

export interface ChatBackupFile {
  text: string;
  fileName: string;
}

export const readBackupFileFromChat = async (): Promise<
  ChatBackupFile | undefined
> => {
  const picked = await wx.chooseMessageFile({ count: 1, type: "file" });
  const file = picked.tempFiles[0];

  if (file === undefined) {
    return undefined;
  }

  const text = await readFileText(file.path);
  const fileName = file.name || "mfa-backup.mfa";

  return { text, fileName };
};

/** CSPRNG：签名是 Promise（基础库 2.15.0+），供 crypto 的 rng 注入使用。 */
export const secureRandom = async (length: number): Promise<Uint8Array> => {
  try {
    const result = await wx.getRandomValues({ length });

    return new Uint8Array(result.randomValues);
  } catch (e: unknown) {
    logger.error("获取安全随机数失败", e);

    throw new Error("当前环境不支持安全随机数");
  }
};
