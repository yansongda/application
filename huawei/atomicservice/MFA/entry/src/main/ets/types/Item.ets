export interface IItem {
  id: string;
  issuer: string;
  username: string;
  code: string;
  config: IItemConfig;
}

export interface IItemConfig {
  period: number;
  // 后端 /totp/all、/totp/detail、/totp/create 返回的大写无填充 base32 明文密钥；
  // 可选以兼容无该字段的历史/异常响应
  secret?: string;
}
