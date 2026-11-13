/**
 * 自建错误基类契约：Error 语义 / code 域 / name / instanceof，以及统一用户文案入口。
 * 微信降级到 ES5 的原型链行为无法在 bun 里复现，只能由真机验证（见计划文档）。
 */
import { describe, expect, it } from "bun:test";
import { CODE, MESSAGE } from "../../src/constant/error";
import {
  BackupParseError,
  BackupParseErrorCode,
} from "../../src/models/backup";
import { AppError, EE, HttpError, WeixinError } from "../../src/models/error";
import error from "../../src/utils/error";

describe("error models", () => {
  it("keeps_http_error_defaults_and_error_semantics", () => {
    const e = new HttpError();

    expect(e.code).toBe(CODE.HTTP);
    expect(e.message).toBe(MESSAGE[CODE.HTTP]);
    expect(e.name).toBe("HttpError");
    expect(e instanceof Error).toBe(true);
    expect(e instanceof EE).toBe(true);
    expect(e instanceof HttpError).toBe(true);
    expect(typeof e.stack).toBe("string");
  });

  it("derives_http_message_from_code_table", () => {
    const e = new HttpError(CODE.HTTP_API_TOTP_ALL);

    expect(e.code).toBe(CODE.HTTP_API_TOTP_ALL);
    expect(e.message).toBe(MESSAGE[CODE.HTTP_API_TOTP_ALL]);
  });

  it("prefers_explicit_message_over_code_table", () => {
    const e = new HttpError(424242, "自定义文案");

    expect(e.code).toBe(424242);
    expect(e.message).toBe("自定义文案");
  });

  it("falls_back_to_unknown_message_for_unmapped_code", () => {
    const e = new EE(424242);

    expect(e.code).toBe(424242);
    expect(e.message).toBe(MESSAGE[CODE.UNKNOWN]);
  });

  it("keeps_weixin_error_default_code_and_name", () => {
    const e = new WeixinError();

    expect(e.code).toBe(CODE.WEIXIN);
    expect(e.message).toBe(MESSAGE[CODE.WEIXIN]);
    expect(e.name).toBe("WeixinError");
    expect(e instanceof EE).toBe(true);
  });

  it("shares_the_base_class_across_code_domains", () => {
    const numeric = new HttpError();
    const string = new BackupParseError(
      BackupParseErrorCode.E_KIND,
      "备份类型不受支持（仅支持 TOTP）",
    );

    expect(numeric instanceof AppError).toBe(true);
    expect(string instanceof AppError).toBe(true);
    expect(string instanceof Error).toBe(true);
    expect(string.code).toBe(BackupParseErrorCode.E_KIND);
    expect(string.message).toBe("备份类型不受支持（仅支持 TOTP）");
    expect(string.name).toBe("BackupParseError");
    expect(string instanceof EE).toBe(false);
  });

  it("freezes_backup_parse_codes", () => {
    const codes = [
      "E_JSON",
      "E_FORMAT",
      "E_KIND",
      "E_VERSION",
      "E_STRUCTURE",
      "E_LIMIT",
    ];

    expect(Object.keys(BackupParseErrorCode).sort()).toEqual([...codes].sort());

    for (const code of codes) {
      expect(
        BackupParseErrorCode[code as keyof typeof BackupParseErrorCode],
      ).toBe(code);
    }
  });

  it("trusts_only_app_error_messages_for_user_text", () => {
    expect(error.getErrorMessage(new HttpError(CODE.HTTP_API_TOTP_ALL))).toBe(
      MESSAGE[CODE.HTTP_API_TOTP_ALL],
    );
    expect(
      error.getErrorMessage(
        new BackupParseError(
          BackupParseErrorCode.E_FORMAT,
          "不是本应用的备份文件",
        ),
      ),
    ).toBe("不是本应用的备份文件");

    // 普通 Error 的内部信息（wx.* errMsg / 英文调试信息）不展示
    expect(error.getErrorMessage(new Error("wx.login failed"))).toBe(
      "操作失败，请重试",
    );
    expect(error.getErrorMessage("not an error")).toBe("操作失败，请重试");
    expect(error.getErrorMessage(null)).toBe("操作失败，请重试");
  });
});
