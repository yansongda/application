import { OtpAlgorithm } from '@yansongda/otp';

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

// 归一化后的条目配置：**每个字段都是确定值**（无 undefined / 无脏值）。
// 归一化唯一入口是 `utils/TotpParams.ets#normalizeConfig`；模型内只存这个形态，
// 因此 UI 与算码逻辑里**不得**再出现 `?? 30` / `?? 6` / `typeof === 'number'` 之类兜底。
// secret 仍为可选：缺失表示「本端不可算码，须回退服务端」。
export interface NormConfig {
  period: number;
  digits: number;
  algorithm: OtpAlgorithm;
  secret?: string;
}
