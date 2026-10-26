import { Secret } from '@yansongda/otp';

// 密钥（Base32）规范化与校验。
// 后端把 otpauth:// 里的 secret 解码成字节后重新编码入库（base32::decode 的
// output_length = len * 5 / 8，向下取整），因此「尾长非法」或「尾部填充位非 0」的
// 文本会被静默截断（例如 GGG 入库变成 GE）。判定完全复用 @yansongda/otp 的
// Secret：解码再编码，只有能原样往返的密钥才放行，语义与后端一致。

// 去 padding 与空白、统一大写：与 @yansongda/otp 内部 decode 的归一化表达式完全一致
// （库源码 internal/Base32.ets: input.replace(/\s/g, '').replace(/=+$/, '').toUpperCase()），
// 保证「比较基准」不会比库本身更严，避免合法的带空白/填充密钥被误判
function normalizeSecret(secret: string): string {
  return secret.replace(/\s/g, '').replace(/=+$/, '').toUpperCase();
}

// 返回可直接提交的规范密钥（大写、无填充）；字符集非法 / 尾长非法 / 填充位非 0 时返回 undefined
function canonicalSecret(secret: string): string | undefined {
  const normalized = normalizeSecret(secret);

  if (0 === normalized.length) {
    return undefined;
  }

  try {
    const canonical: string = Secret.fromBase32(normalized).toBase32();

    // 往返不一致说明后端会静默截断该密钥，直接拦下
    return canonical === normalized ? canonical : undefined;
  } catch (e) {
    // 字符集非法 / 解码为空：库抛 OtpError
    return undefined;
  }
}

// 从 otpauth:// URI 中取出 secret 的原始取值：库只暴露规范化后的值，
// 而「是否会被截断」必须拿原始文本比对，所以这里只做取值、不做 base32 处理
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

// 用规范值就地替换 URI 里的 secret 取值，其余部分原样保留
// （不重建 URI，避免参数顺序/默认值裁剪影响后端解析）
function replaceSecretInUri(uri: string, secret: string): string {
  const queryStart = uri.indexOf('?');

  if (queryStart < 0) {
    return uri;
  }

  const pairs: string[] = [];

  for (const pair of uri.substring(queryStart + 1).split('&')) {
    const separator = pair.indexOf('=');

    if (separator >= 0 && 'secret' === decodeURIComponent(pair.substring(0, separator)).toLowerCase()) {
      pairs.push(`${pair.substring(0, separator + 1)}${secret}`);
      continue;
    }

    pairs.push(pair);
  }

  return `${uri.substring(0, queryStart + 1)}${pairs.join('&')}`;
}

export { canonicalSecret, replaceSecretInUri, secretOfOtpauthUri };
