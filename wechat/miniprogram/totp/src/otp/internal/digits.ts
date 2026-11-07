/**
 * 取模 + 左补零格式化（纯函数，无平台依赖）。
 * 取模是本库唯一发生点；补零用模板字符串，规避平台字符串补位 API 的可用性差异。
 */
import { OtpError, OtpErrorCode } from "../errors";
import { OtpAlgorithm } from "../options";

export function isValidDigits(digits: number): boolean {
  return digits === 6 || digits === 7 || digits === 8;
}

// 构造期防非法算法值穿透到 provider（URI parse 已同规则校验）。
export function isValidAlgorithm(algorithm: OtpAlgorithm): boolean {
  return (
    algorithm === OtpAlgorithm.SHA1 ||
    algorithm === OtpAlgorithm.SHA256 ||
    algorithm === OtpAlgorithm.SHA512
  );
}

export function format(value: number, digits: number): string {
  if (!isValidDigits(digits)) {
    throw new OtpError(OtpErrorCode.INVALID_DIGITS, "INVALID_DIGITS");
  }

  let text = String(value % 10 ** digits);
  while (text.length < digits) {
    text = `0${text}`;
  }
  return text;
}
