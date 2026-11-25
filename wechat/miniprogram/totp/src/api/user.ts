import { endpoint } from "@api/endpoint";
import { CODE } from "@constant/error";
import { PATH } from "@constant/user";
import http from "@utils/http";
import type {
  EditAvatarRequest,
  EditConfigMfaRequest,
  EditNicknameRequest,
  EditSloganRequest,
  MfaConfigSecurity,
  User,
} from "types/user";

const detail = endpoint("查询用户信息失败", CODE.HTTP_API_USER_DETAIL, () =>
  http.post<User>(PATH.DETAIL, {}),
);

const editAvatar = endpoint(
  "更新用户头像失败",
  CODE.HTTP_API_USER_EDIT_AVATAR,
  (avatar: string) =>
    http.post<null>(PATH.EDIT_AVATAR, { avatar } as EditAvatarRequest),
);

const editNickname = endpoint(
  "更新用户昵称失败",
  CODE.HTTP_API_USER_EDIT_NICKNAME,
  (nickname: string) =>
    http.post<null>(PATH.EDIT_NICKNAME, { nickname } as EditNicknameRequest),
);

const editSlogan = endpoint(
  "更新用户 Slogan 失败",
  CODE.HTTP_API_USER_EDIT_SLOGAN,
  (slogan: string) =>
    http.post<null>(PATH.EDIT_SLOGAN, { slogan } as EditSloganRequest),
);

const editConfigMfa = endpoint(
  "更新用户安全设置失败",
  CODE.HTTP_API_USER_EDIT_CONFIG_MFA,
  (security: MfaConfigSecurity) =>
    http.post<null>(PATH.EDIT_CONFIG_MFA, {
      mfa: { security },
    } as EditConfigMfaRequest),
);

const deleteUser = endpoint("注销用户失败", CODE.HTTP_API_USER_DELETE, () =>
  http.post<null>(PATH.DELETE, {}),
);

export default {
  detail,
  editAvatar,
  editNickname,
  editSlogan,
  editConfigMfa,
  deleteUser,
};
