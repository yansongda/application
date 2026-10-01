// 展示兜底：后端/持久化可能给出 null 或空串（''）。
// 注意：`??` 能挡住 null/undefined 但挡不住空串，`typeof === 'undefined'` 又漏掉 null，两者都要判。
export function displayOr(value: string | null | undefined, fallback: Resource): ResourceStr {
  if ('undefined' === typeof value || null === value || 0 === value.length) {
    return fallback;
  }

  return value;
}
