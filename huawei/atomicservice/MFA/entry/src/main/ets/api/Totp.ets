import { IItem } from '../types/Item';
import { request, requestNoBody, requestVoid } from './request';

export interface CreateRequest {
  uri: string;
}

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

// 响应类型统一用 `IItem`：`/totp/all`、`/totp/create` 返回的就是同一个条目结构，
// 之前各自 `extends IItem {}` 的空接口只是三份同义类型。单独刷新条目已由 `/totp/all` 兜底，
// 不再保留 `/totp/detail`（全仓无调用）。
export class Totp {
  static async all(): Promise<IItem[]> {
    return requestNoBody<IItem[]>('api/v1/totp/all');
  }

  static async create(uri: string): Promise<IItem> {
    return request<IItem, CreateRequest>('api/v1/totp/create', { uri });
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
