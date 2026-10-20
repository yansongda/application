export interface IItem {
  id: string;
  issuer: string;
  username: string;
  // 列表标签：后端 config.tags 的投影；旧后端缺省时按空数组处理
  tags?: string[];
  // 是否置顶：后端 config.pinned 的投影；旧后端缺省时按 false 处理
  pinned?: boolean;
  code: string;
  config: IItemConfig;
}

export interface IItemConfig {
  period: number;
  // 后端 /totp/all、/totp/detail、/totp/create 返回的大写无填充 base32 明文密钥；
  // 可选以兼容无该字段的历史/异常响应
  secret?: string;
  // 后端净化后的验证码位数（6~8）与摘要算法（SHA1/SHA256/SHA512）；
  // 可选以兼容 PR #176 之前的历史响应，读取方按 6 / SHA1 兜底
  digits?: number;
  algorithm?: string;
}
