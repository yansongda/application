// 导入计划 / 报告数据结构（纯类型模块，不依赖系统 API，Local Test 可直接加载）。
import { IEnvelopeMeta } from './Envelope';
import { IBackupItem, IInvalidItem } from './Payload';

export class ImportPlanItem {
  readonly item: IBackupItem;
  readonly uri: string;

  constructor(item: IBackupItem, uri: string) {
    this.item = item;
    this.uri = uri;
  }
}

export class ImportPlan {
  readonly accepted: ImportPlanItem[];
  readonly duplicates: number;
  readonly invalid: IInvalidItem[];
  readonly envelopeCount: number;
  readonly meta: IEnvelopeMeta;

  constructor(accepted: ImportPlanItem[], duplicates: number, invalid: IInvalidItem[],
    envelopeCount: number, meta: IEnvelopeMeta) {
    this.accepted = accepted;
    this.duplicates = duplicates;
    this.invalid = invalid;
    this.envelopeCount = envelopeCount;
    this.meta = meta;
  }
}

export class ImportFailure {
  readonly issuer: string;
  readonly username: string;
  readonly stage: string;
  readonly message: string;

  constructor(issuer: string, username: string, stage: string, message: string) {
    this.issuer = issuer;
    this.username = username;
    this.stage = stage;
    this.message = message;
  }
}

export class ImportReport {
  done: number = 0;
  failed: ImportFailure[] = [];
  canceled: boolean = false;
  notExecuted: number = 0;
  withTags: number = 0;
  withPinned: number = 0;
}
