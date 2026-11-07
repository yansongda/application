import type { RequestData } from "./http";

export interface MfaConfigSecurity {
  privacy_window?: boolean | null;
  app_lock?: boolean | null;
}

export interface UserConfigMfa {
  security?: MfaConfigSecurity | null;
}

export interface UserConfig {
  avatar?: string | null;
  nickname?: string | null;
  slogan?: string | null;
  mfa?: UserConfigMfa | null;
}

export interface User {
  phone?: string | null;
  config?: UserConfig | null;
}

export interface EditAvatarRequest extends RequestData {
  avatar: string;
}

export interface EditNicknameRequest extends RequestData {
  nickname: string;
}

export interface EditSloganRequest extends RequestData {
  slogan: string;
}

export interface EditConfigMfaRequest extends RequestData {
  mfa: {
    security: MfaConfigSecurity;
  };
}

// 本地用户缓存：不持久化 mfa（安全设置独立存储键）
export interface UserCache {
  phone?: string | null;
  config: {
    avatar?: string | null;
    nickname?: string | null;
    slogan?: string | null;
  };
}
