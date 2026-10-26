// Base32（RFC 4648）密钥文本校验：与后端 totp-rs / base32 crate 的解码语义对齐。
// 后端会把 otpauth:// 里的 secret 解码成字节、重新编码后入库（base32::decode 的
// output_length = len * 5 / 8，向下取整），所以「尾长非法」或「尾部填充位非 0」的文本
// 会被静默截断（例如 GGG 入库变成 GE）。这里在提交前拦截，避免保存到与二维码不一致的密钥。

const BASE32_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

// 尾部字符数 → 最后一个字符中不参与解码的低位掩码（这些位必须为 0，否则重新编码会变形）
// 2 字符 = 10 bit → 1 字节，余 2 bit；4 字符 = 20 bit → 2 字节，余 4 bit；
// 5 字符 = 25 bit → 3 字节，余 1 bit；7 字符 = 35 bit → 4 字节，余 3 bit。
function tailMask(tail: number): number {
  switch (tail) {
    case 2:
      return 0x03;
    case 4:
      return 0x0F;
    case 5:
      return 0x01;
    case 7:
      return 0x07;
    default:
      return -1;
  }
}

// 归一化：去掉 padding（=）与区分空白，统一大写（RFC 4648 只接受大写字母表）
function normalizeSecret(secret: string): string {
  let normalized = '';

  for (let i = 0; i < secret.length; i++) {
    const char = secret.charAt(i);

    if ('=' === char || ' ' === char || '\n' === char || '\r' === char || '\t' === char) {
      continue;
    }

    normalized += char.toUpperCase();
  }

  return normalized;
}

// 密钥是否可「解码 → 重新编码」无损往返：与后端入库后的值保持一致
function isBase32SecretValid(secret: string): boolean {
  const normalized = normalizeSecret(secret);

  if (0 === normalized.length) {
    return false;
  }

  for (let i = 0; i < normalized.length; i++) {
    if (BASE32_ALPHABET.indexOf(normalized.charAt(i)) < 0) {
      return false;
    }
  }

  const tail = normalized.length % 8;

  // 正好整数个分组时没有填充位
  if (0 === tail) {
    return true;
  }

  const mask = tailMask(tail);

  if (mask < 0) {
    return false;
  }

  const lastValue = BASE32_ALPHABET.indexOf(normalized.charAt(normalized.length - 1));

  return 0 === (lastValue & mask);
}

// 从 otpauth:// URI 中取出 secret 参数（只做提交前的格式预检，不做完整 URI 校验）
function secretOfOtpauthUri(uri: string): string | undefined {
  const queryStart = uri.indexOf('?');

  if (queryStart < 0) {
    return undefined;
  }

  for (const pair of uri.substring(queryStart + 1).split('&')) {
    const separator = pair.indexOf('=');

    if (separator < 0) {
      continue;
    }

    if ('secret' === decodeURIComponent(pair.substring(0, separator)).toLowerCase()) {
      return decodeURIComponent(pair.substring(separator + 1));
    }
  }

  return undefined;
}

// 把 URI 里 secret 参数就地转成大写：部分认证器导出的 URI 用小写 Base32，后端只接受大写字母表
function uppercaseSecretInUri(uri: string): string {
  const queryStart = uri.indexOf('?');

  if (queryStart < 0) {
    return uri;
  }

  const pairs: string[] = [];

  for (const pair of uri.substring(queryStart + 1).split('&')) {
    const separator = pair.indexOf('=');

    if (separator >= 0 && 'secret' === decodeURIComponent(pair.substring(0, separator)).toLowerCase()) {
      pairs.push(`${pair.substring(0, separator + 1)}${pair.substring(separator + 1).toUpperCase()}`);
      continue;
    }

    pairs.push(pair);
  }

  return `${uri.substring(0, queryStart + 1)}${pairs.join('&')}`;
}

export { isBase32SecretValid, normalizeSecret, secretOfOtpauthUri, uppercaseSecretInUri };
