import { CODE } from "@constant/error";
import { PATH } from "@constant/user";
import { HttpError } from "@models/error";
import error from "@utils/error";
import http from "@utils/http";
import logger from "@utils/logger";
import type {
  EditAvatarRequest,
  EditConfigMfaRequest,
  EditNicknameRequest,
  EditSloganRequest,
  MfaConfigSecurity,
  User,
} from "types/user";

const detail = async () => {
  try {
    return await http.post<User>(PATH.DETAIL, {});
  } catch (e: unknown) {
    logger.error("查询用户信息失败", e);

    throw new HttpError(CODE.HTTP_API_USER_DETAIL, error.getErrorMessage(e));
  }
};

const editAvatar = async (avatar: string) => {
  try {
    return await http.post<null>(PATH.EDIT_AVATAR, {
      avatar,
    } as EditAvatarRequest);
  } catch (e: unknown) {
    logger.error("更新用户头像失败", e);

    throw new HttpError(
      CODE.HTTP_API_USER_EDIT_AVATAR,
      error.getErrorMessage(e),
    );
  }
};

const editNickname = async (nickname: string) => {
  try {
    return await http.post<null>(PATH.EDIT_NICKNAME, {
      nickname,
    } as EditNicknameRequest);
  } catch (e: unknown) {
    logger.error("更新用户昵称失败", e);

    throw new HttpError(
      CODE.HTTP_API_USER_EDIT_NICKNAME,
      error.getErrorMessage(e),
    );
  }
};

const editSlogan = async (slogan: string) => {
  try {
    return await http.post<null>(PATH.EDIT_SLOGAN, {
      slogan,
    } as EditSloganRequest);
  } catch (e: unknown) {
    logger.error("更新用户 Slogan 失败", e);

    throw new HttpError(
      CODE.HTTP_API_USER_EDIT_SLOGAN,
      error.getErrorMessage(e),
    );
  }
};

const editConfigMfa = async (security: MfaConfigSecurity) => {
  try {
    return await http.post<null>(PATH.EDIT_CONFIG_MFA, {
      mfa: { security },
    } as EditConfigMfaRequest);
  } catch (e: unknown) {
    logger.error("更新用户安全设置失败", e);

    throw new HttpError(
      CODE.HTTP_API_USER_EDIT_CONFIG_MFA,
      error.getErrorMessage(e),
    );
  }
};

const deleteUser = async () => {
  try {
    return await http.post<null>(PATH.DELETE, {});
  } catch (e: unknown) {
    logger.error("注销用户失败", e);

    throw new HttpError(CODE.HTTP_API_USER_DELETE, error.getErrorMessage(e));
  }
};

export default {
  detail,
  editAvatar,
  editNickname,
  editSlogan,
  editConfigMfa,
  deleteUser,
};
