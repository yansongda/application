import { CODE } from "@constant/error";
import { PATH } from "@constant/totp";
import { HttpError } from "@models/error";
import error from "@utils/error";
import http from "@utils/http";
import logger from "@utils/logger";
import type { RequestData } from "types/http";
import type {
  CreateRequest,
  DeleteRequest,
  DetailRequest,
  EditIssuerRequest,
  EditUsernameRequest,
  Item,
} from "types/totp";

interface SortRequest {
  items: Array<{
    id: string;
    sort: number;
  }>;
}

const all = async () => {
  try {
    return await http.post<Item[]>(PATH.ALL);
  } catch (e: unknown) {
    logger.error("查询 TOTP 列表失败", e);

    throw new HttpError(CODE.HTTP_API_TOTP_ALL, error.getErrorMessage(e));
  }
};

const detail = async (id: string) => {
  try {
    return await http.post<Item>(PATH.DETAIL, { id } as DetailRequest);
  } catch (e: unknown) {
    logger.error("查询 TOTP 详情失败", e);

    throw new HttpError(CODE.HTTP_API_TOTP_DETAIL, error.getErrorMessage(e));
  }
};

const create = async (uri: string) => {
  try {
    return await http.post<null>(PATH.CREATE, { uri } as CreateRequest);
  } catch (e: unknown) {
    logger.error("创建 TOTP 失败", e);

    throw new HttpError(CODE.HTTP_API_TOTP_CREATE, error.getErrorMessage(e));
  }
};

const editIssuer = async (data: EditIssuerRequest) => {
  try {
    return await http.post<null>(PATH.EDIT_ISSUER, data);
  } catch (e: unknown) {
    logger.error("更新 TOTP 的 Issuer 信息失败", e);

    throw new HttpError(
      CODE.HTTP_API_TOTP_EDIT_ISSUER,
      error.getErrorMessage(e),
    );
  }
};

const editUsername = async (data: EditUsernameRequest) => {
  try {
    return await http.post<null>(PATH.EDIT_USERNAME, data);
  } catch (e: unknown) {
    logger.error("更新 TOTP 的 username 信息失败", e);

    throw new HttpError(
      CODE.HTTP_API_TOTP_EDIT_USERNAME,
      error.getErrorMessage(e),
    );
  }
};

const deleteTotp = async (id: string) => {
  try {
    return await http.post<null>(PATH.DELETE, { id } as DeleteRequest);
  } catch (e: unknown) {
    logger.error("删除 TOTP 失败", e);

    throw new HttpError(CODE.HTTP_API_TOTP_DELETE, error.getErrorMessage(e));
  }
};

const sort = async (items: SortRequest["items"]) => {
  try {
    return await http.post<null>(PATH.SORT, { items } as RequestData);
  } catch (e: unknown) {
    logger.error("排序 TOTP 失败", e);

    throw new HttpError(CODE.HTTP_API_TOTP_ALL, error.getErrorMessage(e));
  }
};

export default {
  all,
  detail,
  create,
  editIssuer,
  editUsername,
  deleteTotp,
  sort,
};
