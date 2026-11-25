/**
 * 拖拽排序的纯几何计算：行高、松手落位、重排。零 wx / logger 依赖，可在 Bun 下直接单测。
 *
 * 行高常量必须与 `pages/totp/index.scss` 的 `.sort-row { height: 100px }`、
 * `components/totp/item.scss` 的 `.item { height: 100px }` 保持一致（三处同步改）。
 */
export const ROW_HEIGHT = 100;

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(Math.max(value, min), max);
};

/**
 * 松手时的目标行：起始行号 × 行高 + 拖动位移，四舍五入到最近一行，并夹在 [0, length-1]。
 * 位移来自 `translateY`，因此不需要额外维护每行的绝对 y 坐标。
 */
export const dropIndex = (
  from: number,
  translateY: number,
  length: number,
): number => {
  if (length <= 0) {
    return 0;
  }

  return clamp(
    Math.round((from * ROW_HEIGHT + translateY) / ROW_HEIGHT),
    0,
    length - 1,
  );
};

/** 把 from 处元素移动到 to 位置；返回新数组，不改动入参。 */
export const moveItem = <T>(
  list: readonly T[],
  from: number,
  to: number,
): T[] => {
  const next = [...list];

  if (from < 0 || from >= next.length || from === to) {
    return next;
  }

  const [moved] = next.splice(from, 1);

  next.splice(clamp(to, 0, next.length), 0, moved);

  return next;
};
