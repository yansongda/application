export interface IItem {
  id: string;
  issuer: string;
  username: string;
  code: string;
  config: IItemConfig;
}

export interface IItemConfig {
  period: number;
}
