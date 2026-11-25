import { endpoint } from "@api/endpoint";
import { CODE } from "@constant/error";
import { PATH } from "@constant/totp";
import http from "@utils/http";
import type {
  CreateRequest,
  DeleteRequest,
  EditIssuerRequest,
  EditPinnedRequest,
  EditTagsRequest,
  EditUsernameRequest,
  Item,
} from "types/totp";

interface SortRequest {
  items: Array<{
    id: string;
    sort: number;
  }>;
}

const all = endpoint("查询 TOTP 列表失败", CODE.HTTP_API_TOTP_ALL, () =>
  http.post<Item[]>(PATH.ALL),
);

const create = endpoint(
  "创建 TOTP 失败",
  CODE.HTTP_API_TOTP_CREATE,
  (uri: string) => http.post<Item>(PATH.CREATE, { uri } as CreateRequest),
);

const editIssuer = endpoint(
  "更新 TOTP 的 Issuer 信息失败",
  CODE.HTTP_API_TOTP_EDIT_ISSUER,
  (data: EditIssuerRequest) => http.post<null>(PATH.EDIT_ISSUER, data),
);

const editUsername = endpoint(
  "更新 TOTP 的 username 信息失败",
  CODE.HTTP_API_TOTP_EDIT_USERNAME,
  (data: EditUsernameRequest) => http.post<null>(PATH.EDIT_USERNAME, data),
);

const editTags = endpoint(
  "更新 TOTP 的标签失败",
  CODE.HTTP_API_TOTP_EDIT_TAGS,
  (data: EditTagsRequest) => http.post<null>(PATH.EDIT_TAGS, data),
);

const editPinned = endpoint(
  "更新 TOTP 的置顶状态失败",
  CODE.HTTP_API_TOTP_EDIT_PINNED,
  (data: EditPinnedRequest) => http.post<null>(PATH.EDIT_PINNED, data),
);

const deleteTotp = endpoint(
  "删除 TOTP 失败",
  CODE.HTTP_API_TOTP_DELETE,
  (id: string) => http.post<null>(PATH.DELETE, { id } as DeleteRequest),
);

const sort = endpoint(
  "排序 TOTP 失败",
  CODE.HTTP_API_TOTP_SORT,
  (items: SortRequest["items"]) => http.post<null>(PATH.SORT, { items }),
);

export default {
  all,
  create,
  editIssuer,
  editUsername,
  editTags,
  editPinned,
  deleteTotp,
  sort,
};
