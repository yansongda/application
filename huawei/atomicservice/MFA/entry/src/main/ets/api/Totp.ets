import { AxiosResponse } from '@ohos/axios';
import { IItem } from '../types/Item';
import http, { HttpError, Response } from '../utils/Http';

export interface AllResponse extends IItem {}

export interface CreateRequest {
  uri: string;
}

export interface CreateResponse extends IItem {}

export interface DetailRequest {
  id: string;
}

export interface DetailResponse extends IItem {}

export interface EditIssuerRequest {
  id: string;
  issuer: string;
}

export interface EditUsernameRequest {
  id: string;
  username: string;
}

export interface DeleteRequest {
  id: string;
}

export interface SortRequest {
  items: Array<SortRequestItem>;
}

export interface SortRequestItem {
  id: string;
  sort: number;
}


export interface SortResponse {}

export class Totp {
  static async all(): Promise<Set<AllResponse>> {
    const response: AxiosResponse<Response<Set<AllResponse>>> =
      await http.post<Set<AllResponse>, AxiosResponse<Response<Set<AllResponse>>>, null>('api/v1/totp/all');

    if (0 === response.data?.code && response.data.data) {
      return response.data.data;
    }

    return Promise.reject(new HttpError(response.data.message));
  }

  static async create(uri: string): Promise<CreateResponse> {
    const response: AxiosResponse<Response<CreateResponse>> =
      await http.post<CreateResponse, AxiosResponse<Response<CreateResponse>>, CreateRequest>('api/v1/totp/create',
        {
          uri,
        });

    if (response.data?.data?.id) {
      return response.data.data;
    }

    return Promise.reject(new HttpError(response.data.message));
  }

  static async detail(id: string): Promise<DetailResponse> {
    const response: AxiosResponse<Response<DetailResponse>> =
      await http.post<DetailResponse, AxiosResponse<Response<DetailResponse>>, DetailRequest>('api/v1/totp/detail',
        {
          id,
        });

    if (response.data?.data?.id) {
      return response.data.data;
    }

    return Promise.reject(new HttpError(response.data.message));
  }

  static async editIssuer(id: string, issuer: string): Promise<void> {
    const response: AxiosResponse<Response<void>> =
      await http.post<void, AxiosResponse<Response<void>>, EditIssuerRequest>('api/v1/totp/edit/issuer',
        {
          id,
          issuer,
        });

    if (0 === response.data?.code) {
      return;
    }

    return Promise.reject(new HttpError(response.data.message));
  }

  static async editUsername(id: string, username: string): Promise<void> {
    const response: AxiosResponse<Response<void>> =
      await http.post<void, AxiosResponse<Response<void>>, EditUsernameRequest>('api/v1/totp/edit/username',
        {
          id,
          username,
        });

    if (0 === response.data?.code) {
      return;
    }

    return Promise.reject(new HttpError(response.data.message));
  }

  static async delete(id: string): Promise<void> {
    const response: AxiosResponse<Response<void>> =
      await http.post<void, AxiosResponse<Response<void>>, DeleteRequest>('api/v1/totp/delete',
        {
          id,
        });

    if (0 === response.data?.code) {
      return;
    }

    return Promise.reject(new HttpError(response.data.message));
  }

  static async sort(items: Array<SortRequestItem>): Promise<void> {
    const response: AxiosResponse<Response<SortResponse>> =
      await http.post<SortResponse, AxiosResponse<Response<SortResponse>>, SortRequest>('api/v1/totp/sort',
        {
          items,
        });

    if (0 === response.data?.code) {
      return;
    }

    return Promise.reject(new HttpError(response.data.message));
  }
}
