// 展示兜底：后端可能返回空串（''），直接用 `??` 会当成「有值」而展示为空白，这里统一按「无值」处理
export function displayOr(value: string | undefined, fallback: Resource): ResourceStr {
  return 'undefined' === typeof value || 0 === value.length ? fallback : value;
}
