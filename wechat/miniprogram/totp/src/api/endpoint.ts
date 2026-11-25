/**
 * 业务接口统一包装：真实请求 → 失败日志 → 抛带业务码的 `HttpError`。
 *
 * 各 `api/*.ts` 只声明「日志标签 + 业务码 + 请求体」，不再逐函数复制同一份 try/catch。
 * `HttpError` 的 message 仍沿用 `utils/error.ts#getErrorMessage`（只信任 `AppError` 的文案），
 * 因此页面侧的错误提示语义不变；`describe` 用于需要额外码表映射的接口（如加密备份）。
 */
import { HttpError } from "@models/error";
import error from "@utils/error";
import logger from "@utils/logger";

type Mapper<A extends unknown[], R> = (...args: A) => Promise<R>;

const endpoint = <A extends unknown[], R>(
  label: string,
  code: number,
  call: Mapper<A, R>,
  describe?: (e: unknown) => string,
): Mapper<A, R> => {
  return async (...args: A): Promise<R> => {
    try {
      return await call(...args);
    } catch (e: unknown) {
      logger.error(label, e);

      throw new HttpError(
        code,
        describe === undefined ? error.getErrorMessage(e) : describe(e),
      );
    }
  };
};

export { endpoint };
