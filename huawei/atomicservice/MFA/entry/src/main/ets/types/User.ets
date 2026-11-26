// 用户资料的后端契约（叶子类型）：只放接口与字段，不 import 任何业务模块。
//
// 为什么单独成文件：`api/User.ets` 需要这些类型，`models/security/Sync.ets` 需要
// `api/User` —— 把契约类型留在 `models/User.ets` 里会让 `api → models` 反向依赖
// （`types/Session.ets`、`types/Login.ets` 也是同一理由拆出来的）。
// `models/User.ets` 只保留被观测的 `Config` / `User` 类。

export interface IMfaConfigSecurity {
  // 字段名与后端 `config.mfa.security` 一致（snake_case），与端上 preferences 一一对应
  privacy_window?: boolean | null;
  app_lock?: boolean | null;
}

export interface IConfigMfa {
  security?: IMfaConfigSecurity | null;
}

// 接口返回的是普通 JSON（不是被观测的类实例），因此对外只承诺这些字段
export interface IUserConfig {
  avatar?: string | null;
  nickname?: string | null;
  slogan?: string | null;
  // MFA 安全设置的云端副本：老数据无该字段，读取方按「服务端未保存过」处理
  mfa?: IConfigMfa | null;
}

export interface IUser {
  phone?: string | null;
  config?: IUserConfig | null;
}
