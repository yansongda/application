import { AxiosResponse } from '@ohos/axios';
import { User as UserModel } from '../models/User';
import http, { HttpError, Response } from '../utils/Http';

export interface EditAvatarRequest {
  avatar: string;
}

export interface EditNicknameRequest {
  nickname: string;
}

export interface EditSloganRequest {
  slogan: string;
}

export class User {
  static async detail(): Promise<UserModel> {
    const response: AxiosResponse<Response<UserModel>> =
      await http.post<UserModel, AxiosResponse<Response<UserModel>>, void>('api/v1/users/detail');

    if (0 === response.data?.code && response.data.data) {
      return response.data.data;
    }

    return Promise.reject(new HttpError(response.data?.message ?? '请求失败'));
  }

  static async editAvatar(avatar: string): Promise<void> {
    const response: AxiosResponse<Response<void>> =
      await http.post<void, AxiosResponse<Response<void>>, EditAvatarRequest>('api/v1/users/edit/avatar',
        {
          avatar,
        });

    if (0 === response.data?.code) {
      return;
    }

    return Promise.reject(new HttpError(response.data?.message ?? '请求失败'));
  }

  static async editNickname(nickname: string): Promise<void> {
    const response: AxiosResponse<Response<void>> =
      await http.post<void, AxiosResponse<Response<void>>, EditNicknameRequest>('api/v1/users/edit/nickname',
        {
          nickname,
        });

    if (0 === response.data?.code) {
      return;
    }

    return Promise.reject(new HttpError(response.data?.message ?? '请求失败'));
  }

  static async editSlogan(slogan: string): Promise<void> {
    const response: AxiosResponse<Response<void>> =
      await http.post<void, AxiosResponse<Response<void>>, EditSloganRequest>('api/v1/users/edit/slogan',
        {
          slogan,
        });

    if (0 === response.data?.code) {
      return;
    }

    return Promise.reject(new HttpError(response.data?.message ?? '请求失败'));
  }

  static async delete(): Promise<void> {
    const response: AxiosResponse<Response<void>> =
      await http.post<void, AxiosResponse<Response<void>>, void>('api/v1/users/delete');

    if (0 === response.data?.code) {
      return;
    }

    return Promise.reject(new HttpError(response.data?.message ?? '请求失败'));
  }
}