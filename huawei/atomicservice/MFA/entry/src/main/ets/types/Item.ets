export interface IItem {
  id: string;
  issuer: string;
  username: string;
  code: string;
  sort: number;
  config: IItemConfig;
}

export interface IItemConfig {
  period: number;
}
