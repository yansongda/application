/**
 * 本地时间显示（导入 / 导出页使用）。
 *
 * 解析交给 `src/backup/time.ts`（严格、平台无关）；这里只负责按设备本地时区渲染，
 * 不做任何时区/格式推断，避免两端或不同 locale 出现不同显示。
 */
import { parseCreatedAt } from "../backup/time";

const pad = (value: number): string => {
  return value.toString().padStart(2, "0");
};

/** `YYYY-MM-DD HH:mm`（本地时区）；解析失败回退原串，不显示 Invalid Date。 */
export const formatLocalDateTime = (iso: string): string => {
  const parsed = parseCreatedAt(iso);

  if (parsed === undefined) {
    return iso;
  }

  const date = new Date(parsed.epochMs);

  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
};
