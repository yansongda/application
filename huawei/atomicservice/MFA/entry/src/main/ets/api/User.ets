import { IMfaConfigSecurity, IUser } from '../models/User';
import { request, requestNoBody, requestVoid, requestVoidNoBody } from './request';

export interface EditAvatarRequest {
  avatar: string;
}

export interface EditConfigMfaBody {
  security: IMfaConfigSecurity;
}

export interface EditConfigMfaRequest {
  mfa: EditConfigMfaBody;
}

export interface EditNicknameRequest {
  nickname: string;
}

export interface EditSloganRequest {
  slogan: string;
}

export class User {
  static async detail(): Promise<IUser> {
    return requestNoBody<IUser>('api/v1/users/detail');
  }

  static async editAvatar(avatar: string): Promise<void> {
    return requestVoid<EditAvatarRequest>('api/v1/users/edit/avatar', { avatar });
  }

  static async editNickname(nickname: string): Promise<void> {
    return requestVoid<EditNicknameRequest>('api/v1/users/edit/nickname', { nickname });
  }

  static async editSlogan(slogan: string): Promise<void> {
    return requestVoid<EditSloganRequest>('api/v1/users/edit/slogan', { slogan });
  }

  // 安全设置云端副本：`config.mfa.security`（后端按叶子 merge，未传的字段保持原值）
  static async editConfigMfa(security: IMfaConfigSecurity): Promise<void> {
    const body: EditConfigMfaRequest = { mfa: { security: security } };

    return requestVoid<EditConfigMfaRequest>('api/v1/users/edit/config/mfa', body);
  }

  static async delete(): Promise<void> {
    return requestVoidNoBody('api/v1/users/delete');
  }
}
