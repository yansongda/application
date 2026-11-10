/**
 * 时间显示与严格解析（后端信封 `meta.created_at`：带时区偏移的 RFC3339）。
 *
 * 手写解析，不依赖 `Date.parse`：老 JSCore 对带偏移 ISO 串的解析行为不可靠；
 * 备份预检需要与后端一致地拒绝非法时间，因此保留严格校验。
 */

const TIMESTAMP_PATTERN =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|([+-])(\d{2}):(\d{2}))$/;

const MIN_YEAR = 1970;

const pad = (value: number): string => {
  return value.toString().padStart(2, "0");
};

export interface ParsedCreatedAt {
  /** 绝对时刻（epoch 毫秒）；显示时再按设备本地时区格式化。 */
  epochMs: number;
  /** 文件中声明的时区偏移（分钟，东区为正），仅用于排障/显示原始时区。 */
  offsetMinutes: number;
}

/** 严格解析：格式非法或日历非法（如 2026-02-30）一律返回 undefined。 */
export const parseCreatedAt = (text: string): ParsedCreatedAt | undefined => {
  const match = TIMESTAMP_PATTERN.exec(text);

  if (match === null) {
    return undefined;
  }

  // 正则已限定 4 位年份（≤9999），这里只需拦住 1970 之前的值
  const year = Number(match[1]);

  if (year < MIN_YEAR) {
    return undefined;
  }

  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);

  if (
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > 31 ||
    hour > 23 ||
    minute > 59 ||
    second > 59
  ) {
    return undefined;
  }

  const millis =
    match[7] === undefined ? 0 : Number(match[7].slice(0, 3).padEnd(3, "0"));

  let offsetMinutes = 0;

  if (match[8] !== "Z") {
    const offsetHours = Number(match[10]);
    const offsetMins = Number(match[11]);

    if (offsetHours > 14 || offsetMins > 59) {
      return undefined;
    }

    if (offsetHours === 14 && offsetMins !== 0) {
      return undefined;
    }

    offsetMinutes =
      (offsetHours * 60 + offsetMins) * (match[9] === "-" ? -1 : 1);
  }

  const wallClockMs = Date.UTC(
    year,
    month - 1,
    day,
    hour,
    minute,
    second,
    millis,
  );
  const epochMs = wallClockMs - offsetMinutes * 60000;

  // 日历往返校验：拒绝 2026-02-30 / 2026-13-01 这类正则挡不住的非法日期
  const check = new Date(wallClockMs);

  if (
    check.getUTCFullYear() !== year ||
    check.getUTCMonth() !== month - 1 ||
    check.getUTCDate() !== day ||
    check.getUTCHours() !== hour ||
    check.getUTCMinutes() !== minute ||
    check.getUTCSeconds() !== second ||
    check.getUTCMilliseconds() !== millis
  ) {
    return undefined;
  }

  return { epochMs, offsetMinutes };
};

/** `YYYY-MM-DD HH:mm`（设备本地时区）；解析失败回退原串，不显示 Invalid Date。 */
export const formatLocalDateTime = (iso: string): string => {
  const parsed = parseCreatedAt(iso);

  if (parsed === undefined) {
    return iso;
  }

  const date = new Date(parsed.epochMs);

  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
};
