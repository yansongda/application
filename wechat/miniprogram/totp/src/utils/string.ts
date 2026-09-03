export function substr(data: string, maxWidth?: number): string {
  const width = maxWidth || 24; // 默认最大宽度为24个单位
  let nextWidth = 0;
  let result = "";

  for (let i = 0; i < data.length; i++) {
    const char = data[i];
    // biome-ignore lint: 就是需要检测中文
    const charWidth = /[^\x00-\xff]/.test(char) ? 2 : 1;

    nextWidth += charWidth;

    if (nextWidth > width) {
      break;
    }

    result += char;
  }

  return data.length > result.length ? `${result}...` : result;
}
