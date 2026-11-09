/**
 * 备份时间戳编解码测试（规范 §4.1 / §7）。
 * formatCreatedAt 用 UTC getter 平移实现，因此断言与运行环境时区无关。
 */
import { describe, expect, it } from "bun:test";
import { formatCreatedAt, parseCreatedAt } from "../../src/backup/time";

describe("backup time", () => {
  it("format_usesOffsetAndFixedMillis", () => {
    const date = new Date("2026-11-07T00:00:00.000Z");

    expect(formatCreatedAt(date, 480)).toBe("2026-11-07T08:00:00.000+08:00");
    expect(formatCreatedAt(date, -300)).toBe("2026-11-06T19:00:00.000-05:00");
    expect(formatCreatedAt(date, 345)).toBe("2026-11-07T05:45:00.000+05:45");
    expect(formatCreatedAt(date, 0)).toBe("2026-11-07T00:00:00.000+00:00");
    expect(formatCreatedAt(new Date("2026-11-07T00:00:00.007Z"), 480)).toBe(
      "2026-11-07T08:00:00.007+08:00",
    );
  });

  it("format_crossesDateBoundary", () => {
    expect(formatCreatedAt(new Date("2026-11-07T20:00:00.000Z"), 480)).toBe(
      "2026-11-08T04:00:00.000+08:00",
    );
  });

  it("parse_acceptsAllLegalForms", () => {
    const cases: Array<[string, string]> = [
      ["2026-11-07T08:00:00.000+08:00", "2026-11-07T00:00:00.000Z"],
      ["2026-11-07T00:00:00.000+00:00", "2026-11-07T00:00:00.000Z"],
      ["2026-11-07T00:00:00.000Z", "2026-11-07T00:00:00.000Z"],
      ["2026-11-06T19:00:00.000-05:00", "2026-11-07T00:00:00.000Z"],
      ["2026-11-07T12:15:00.000+05:45", "2026-11-07T06:30:00.000Z"],
      ["2026-11-07T08:00:00.5+08:00", "2026-11-07T00:00:00.500Z"],
      ["2026-11-07T08:00:00+08:00", "2026-11-07T00:00:00.000Z"],
    ];

    for (const [text, iso] of cases) {
      expect(parseCreatedAt(text)?.epochMs).toBe(Date.parse(iso));
    }
  });

  it("parse_roundTripsFormat", () => {
    const date = new Date(Date.UTC(2026, 10, 7, 3, 4, 5, 678));

    for (const offset of [-720, -300, 0, 330, 345, 480, 840]) {
      const text = formatCreatedAt(date, offset);
      const parsed = parseCreatedAt(text);

      expect(parsed?.epochMs).toBe(date.getTime());
      expect(parsed?.offsetMinutes).toBe(offset);
    }
  });

  it("parse_rejectsIllegal", () => {
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
      "2026-11-07T00:00:00.0000Z",
    ];

    for (const text of illegal) {
      expect(parseCreatedAt(text)).toBeUndefined();
    }
  });

  it("format_rejectsOutOfRangeOffset", () => {
    const date = new Date(Date.UTC(2026, 10, 7));

    expect(() => formatCreatedAt(date, 841)).toThrow();
    expect(() => formatCreatedAt(date, -841)).toThrow();
    expect(() => formatCreatedAt(date, 1.5)).toThrow();
  });
});

describe("local datetime display", () => {
  it("formatLocalDateTime_fallsBackOnIllegalInput", async () => {
    const { formatLocalDateTime } = await import("../../src/utils/datetime");

    expect(formatLocalDateTime("not-a-time")).toBe("not-a-time");
    expect(formatLocalDateTime("2026-02-30T00:00:00.000Z")).toBe(
      "2026-02-30T00:00:00.000Z",
    );
  });

  it("formatLocalDateTime_rendersValidTimestampAsLocalWallClock", async () => {
    const { formatLocalDateTime } = await import("../../src/utils/datetime");
    const text = formatLocalDateTime("2026-11-07T08:00:00.000+08:00");

    expect(text).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/);
  });
});
