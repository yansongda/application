import { IItem } from '../types/Item';
import { request, requestNoBody, requestVoid } from './request';

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

export interface EditTagsRequest {
  id: string;
  tags: string[];
}

export interface EditPinnedRequest {
  id: string;
  pinned: boolean;
}

export interface SortRequest {
  items: Array<SortRequestItem>;
}

export interface SortRequestItem {
  id: string;
  sort: number;
}

export class Totp {
  static async all(): Promise<AllResponse[]> {
    return requestNoBody<AllResponse[]>('api/v1/totp/all');
  }

  static async create(uri: string): Promise<CreateResponse> {
    return request<CreateResponse, CreateRequest>('api/v1/totp/create', { uri });
  }

  static async detail(id: string): Promise<DetailResponse> {
    return request<DetailResponse, DetailRequest>('api/v1/totp/detail', { id });
  }

  static async editIssuer(id: string, issuer: string): Promise<void> {
    return requestVoid<EditIssuerRequest>('api/v1/totp/edit/issuer', { id, issuer });
  }

  static async editUsername(id: string, username: string): Promise<void> {
    return requestVoid<EditUsernameRequest>('api/v1/totp/edit/username', { id, username });
  }

  static async editTags(id: string, tags: string[]): Promise<void> {
    return requestVoid<EditTagsRequest>('api/v1/totp/edit/tags', { id, tags });
  }

  static async editPinned(id: string, pinned: boolean): Promise<void> {
    return requestVoid<EditPinnedRequest>('api/v1/totp/edit/pinned', { id, pinned });
  }

  static async delete(id: string): Promise<void> {
    return requestVoid<DeleteRequest>('api/v1/totp/delete', { id });
  }

  static async sort(items: Array<SortRequestItem>): Promise<void> {
    return requestVoid<SortRequest>('api/v1/totp/sort', { items });
  }
}
