import { EE } from "@models/error";

const getErrorMessage = (e: unknown) => {
  return e instanceof Error || e instanceof EE ? e.message : "未知异常";
};

export default { getErrorMessage };
