/**
 * 备份时间戳编解码（规范 §4.1 / §7）。
 *
 * - 导出端写入：`YYYY-MM-DDTHH:mm:ss.SSS±HH:mm`（毫秒固定 3 位，偏移 0 写 `+00:00`，不写 `Z`）
 * - 导入端接受：同上，另外允许省略毫秒（0~3 位）与 UTC 记 `Z`
 * - 手写解析，不依赖 `Date.parse`：老 JSCore 对带偏移 ISO 串的解析行为不可靠，
 *   而 createdAt 现在参与 AAD（规范 §4.2），解析结果不能再有平台差异
 *
 * 纯函数模块：不依赖 wx / logger，也不引入 `Math.random` / `BigInt`（库不变量）。
 */

const TIMESTAMP_PATTERN =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(Z|([+-])(\d{2}):(\d{2}))$/;

const MAX_OFFSET_MINUTES = 14 * 60;
const MIN_YEAR = 1970;
const MAX_YEAR = 9999;

const pad = (value: number): string => {
  return value.toString().padStart(2, "0");
};

/**
 * 按给定时区偏移格式化时间戳（规范 §4.1）。
 * `offsetMinutes` 为「本地相对 UTC 的偏移」：东八区传 `480`，西五区传 `-300`。
 * 用 UTC getter + 平移实现：结果与运行环境时区无关，便于确定性测试。
 */
export const formatCreatedAt = (date: Date, offsetMinutes: number): string => {
  if (
    !Number.isInteger(offsetMinutes) ||
    Math.abs(offsetMinutes) > MAX_OFFSET_MINUTES
  ) {
    throw new Error("时区偏移必须是 ±14:00 内的整分钟");
  }

  const shifted = new Date(date.getTime() + offsetMinutes * 60000);
  const sign = offsetMinutes < 0 ? "-" : "+";
  const abs = Math.abs(offsetMinutes);
  const days = `${shifted.getUTCFullYear()}-${pad(shifted.getUTCMonth() + 1)}-${pad(shifted.getUTCDate())}`;
  const time = `${pad(shifted.getUTCHours())}:${pad(shifted.getUTCMinutes())}:${pad(shifted.getUTCSeconds())}`;
  const millis = shifted.getUTCMilliseconds().toString().padStart(3, "0");

  return `${days}T${time}.${millis}${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`;
};

export interface ParsedCreatedAt {
  /** 绝对时刻（epoch 毫秒）；显示时再按设备本地时区格式化。 */
  epochMs: number;
  /** 文件中声明的时区偏移（分钟，东区为正），仅用于排障/显示原始时区。 */
  offsetMinutes: number;
}

/**
 * 严格解析 createdAt：格式非法或日历非法（如 2026-02-30）一律返回 undefined。
 * 导入端据此映射 `E_STRUCTURE`（规范 §8 步骤 4）。
 */
export const parseCreatedAt = (text: string): ParsedCreatedAt | undefined => {
  const match = TIMESTAMP_PATTERN.exec(text);

  if (match === null) {
    return undefined;
  }

  const year = Number(match[1]);

  if (year < MIN_YEAR || year > MAX_YEAR) {
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

  const millis = match[7] === undefined ? 0 : Number(match[7].padEnd(3, "0"));

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
