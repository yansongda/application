/**
 * 时间解析 / 本地显示测试（后端信封 meta.created_at）。
 */
import { describe, expect, it } from "bun:test";
import { formatLocalDateTime, parseCreatedAt } from "../../src/utils/datetime";

describe("datetime parse", () => {
  it("accepts_all_legal_forms", () => {
    const cases: Array<[string, string]> = [
      ["2026-11-07T08:00:00.000+08:00", "2026-11-07T00:00:00.000Z"],
      ["2026-11-07T00:00:00.000+00:00", "2026-11-07T00:00:00.000Z"],
      ["2026-11-07T00:00:00.000Z", "2026-11-07T00:00:00.000Z"],
      ["2026-11-06T19:00:00.000-05:00", "2026-11-07T00:00:00.000Z"],
      ["2026-11-07T12:15:00.000+05:45", "2026-11-07T06:30:00.000Z"],
      ["2026-11-07T08:00:00.5+08:00", "2026-11-07T00:00:00.500Z"],
      ["2026-11-07T08:00:00.123456+08:00", "2026-11-07T00:00:00.123Z"],
      ["2026-11-07T08:00:00+08:00", "2026-11-07T00:00:00.000Z"],
    ];

    for (const [text, iso] of cases) {
      expect(parseCreatedAt(text)?.epochMs).toBe(Date.parse(iso));
    }
  });

  it("rejects_illegal_forms", () => {
    const illegal = [
      "",
      "2026-11-07",
      "2026-11-07T08:00:00",
      "2026-11-07T08:00:00+0800",
      "2026-13-01T00:00:00.000Z",
      "2026-02-30T00:00:00.000Z",
      "2026-11-07T24:00:00.000Z",
      "2026-11-07T00:60:00.000Z",
      "2026-11-07T00:00:60.000Z",
      "2026-11-07T00:00:00.000+14:01",
      "2026-11-07T00:00:00.000+15:00",
      "1969-12-31T23:59:59.000Z",
      "226-11-07T00:00:00.000Z",
      " 2026-11-07T00:00:00.000Z",
      "2026-11-07T00:00:00.Z",
    ];

    for (const text of illegal) {
      expect(parseCreatedAt(text)).toBeUndefined();
    }
  });
});

describe("local datetime display", () => {
  it("falls_back_on_illegal_input", () => {
    expect(formatLocalDateTime("not-a-time")).toBe("not-a-time");
    expect(formatLocalDateTime("2026-02-30T00:00:00.000Z")).toBe(
      "2026-02-30T00:00:00.000Z",
    );
  });

  it("renders_valid_timestamp_as_local_wall_clock", () => {
    const text = formatLocalDateTime("2026-11-07T08:00:00.000+08:00");

    expect(text).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/);
  });
});
