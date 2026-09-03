const PATH = {
  LOGIN: "/api/v1/access-token/login",
  REFRESH: "/api/v1/access-token/login/refresh",
  VALID: "/api/v1/access-token/valid",
};

const PLATFORM = "wechat";

const { appId } = wx.getAccountInfoSync().miniProgram;

export { appId as THIRD_ID, PATH, PLATFORM };
