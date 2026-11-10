/**
 * 备份文件通道（微信侧唯一 wx 文件入口）：
 * - 导出：写 USER_DATA_PATH 后由用户点击转发（wx.shareFileMessage 必须用户触发）
 * - 导入：从聊天选择文件并读文本（wx.chooseMessageFile，不依赖后缀）
 * 加密/解密全部在服务端完成；本模块不触碰口令，也不打日志内容。
 */
export interface BackupFile {
  filePath: string;
  fileName: string;
}

const pad = (value: number): string => {
  return value.toString().padStart(2, "0");
};

/** 推荐命名 mfa-backup-YYYYMMDD-HHmm.mfa（后缀沿用小程序文案约定，内容为后端信封 JSON）。 */
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
