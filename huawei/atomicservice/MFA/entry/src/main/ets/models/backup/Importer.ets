// 导入编排：结构校验 → 解密 → 计划（accepted / duplicates / invalid）→ 串行 create + 校正。
//
// 凭证重建策略（规范 §6.2，两端逐字一致）：
//   uriIssuer = (issuer 含 ":" || issuer === "") ? "__mfa__" : issuer
// 创建成功后按响应比对并 editIssuer/editUsername 校正（totp-rs 在 label 首个冒号处切分，
// issuer 含冒号会串位甚至报 IssuerMismatch）。
import { OtpAlgorithm, OTPAuthURI, OtpType } from '@yansongda/otp';
import { IItem } from '../../types/Item';
import { Totp } from '../../api/Totp';
import { ItemsRuntime } from '../totp/ItemsRuntime';
import { BackupCrypto } from './Crypto';
import { decodeBase64Strict, parseEnvelope } from './Envelope';
import { IEnvelope } from './Envelope';
import {
  ImportFailure,
  ImportPlan,
  ImportPlanItem,
  ImportReport
} from './ImportTypes';
import { dedupeKey, IBackupItem, parsePayload, PayloadParseResult } from './Payload';
import { BackupError, BackupErrorCode, BackupSpec, planUriIssuer } from './Spec';

function existingKeySet(existing: IItem[]): Set<string> {
  const keys: Set<string> = new Set<string>();

  for (const item of existing) {
    const secret: string | undefined = item.config.secret;

    // 本地条目缺 secret 时不参与去重比较（规范 §6.1）
    if ('undefined' === typeof secret || secret.length === 0) {
      continue;
    }

    keys.add(`${secret}|${item.issuer}|${item.username}`);
  }

  return keys;
}

function toAlgorithm(algorithm: string): OtpAlgorithm {
  switch (algorithm) {
    case 'SHA256':
      return OtpAlgorithm.SHA256;
    case 'SHA512':
      return OtpAlgorithm.SHA512;
    default:
      return OtpAlgorithm.SHA1;
  }
}

function describeError(e: Object): string {
  const error: Error = e as Error;

  return 'undefined' !== typeof error.message ? error.message : '操作失败';
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) {
    return false;
  }

  let diff: number = 0;

  for (let i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }

  return 0 === diff;
}

export class Importer {
  // 结构错误/解密错误抛 BackupError；单条非法只计入 invalid，不阻塞整包
  static async analyze(text: string, password: string, existing: IItem[]): Promise<ImportPlan> {
    const parsed = parseEnvelope(text);

    if (!parsed.ok || 'undefined' === typeof parsed.envelope) {
      throw new BackupError(parsed.code, parsed.detail);
    }

    const envelope: IEnvelope = parsed.envelope;
    const salt: Uint8Array = decodeBase64Strict(envelope.key.salt);
    const iv: Uint8Array = decodeBase64Strict(envelope.key.iv);
    const tag: Uint8Array = decodeBase64Strict(envelope.key.tag);
    const expectedKcv: Uint8Array = decodeBase64Strict(envelope.key.kcv);
    const key: Uint8Array = await BackupCrypto.deriveKey(password, salt, envelope.key.iterations);

    if (!constantTimeEqual(await BackupCrypto.kcv(key), expectedKcv)) {
      throw new BackupError(BackupErrorCode.E_PASSWORD);
    }

    const plaintext: Uint8Array | undefined = await BackupCrypto.decrypt(key, iv,
      BackupCrypto.utf8Bytes(BackupSpec.AAD), decodeBase64Strict(envelope.data), tag);

    if ('undefined' === typeof plaintext) {
      throw new BackupError(BackupErrorCode.E_CORRUPT);
    }

    const payload: PayloadParseResult = parsePayload(BackupCrypto.utf8Text(plaintext));

    if (!payload.ok) {
      throw new BackupError(payload.code, payload.detail);
    }

    if (payload.items.length + payload.invalid.length !== envelope.meta.count) {
      throw new BackupError(BackupErrorCode.E_PAYLOAD, 'meta.count 与解密条目数不一致');
    }

    const known: Set<string> = existingKeySet(existing);
    const accepted: ImportPlanItem[] = [];
    let duplicates: number = 0;

    for (const item of payload.items) {
      const keyOfItem: string = dedupeKey(item.secret, item.issuer, item.username);

      if (known.has(keyOfItem)) {
        duplicates++;
        continue;
      }

      known.add(keyOfItem);

      const uri: string = OTPAuthURI.build({
        type: OtpType.TOTP,
        secret: item.secret,
        algorithm: toAlgorithm(item.algorithm),
        digits: item.digits,
        period: item.period,
        issuer: planUriIssuer(item.issuer),
        account: item.username
      });

      accepted.push(new ImportPlanItem(item, uri));
    }

    return new ImportPlan(accepted, duplicates, payload.invalid, envelope.meta.count, envelope.meta);
  }

  // 串行执行：create → 校正 issuer/username → tags/pinned；单条失败不中断，校正失败不回滚
  static async run(plan: ImportPlan, itemsRuntime: ItemsRuntime,
    onProgress: (done: number, total: number) => void,
    shouldCancel: () => boolean): Promise<ImportReport> {
    const total: number = plan.accepted.length;
    const report: ImportReport = new ImportReport();

    for (let index = 0; index < total; index++) {
      if (shouldCancel()) {
        report.canceled = true;
        report.notExecuted = total - index;
        break;
      }

      const entry: ImportPlanItem = plan.accepted[index];
      const item: IBackupItem = entry.item;
      let stage: string = 'create';

      try {
        const created: IItem = await Totp.create(entry.uri);

        report.done++;

        stage = 'issuer';

        let issuer: string = created.issuer;
        let username: string = created.username;

        if (created.issuer !== item.issuer) {
          await Totp.editIssuer(created.id, item.issuer);
          issuer = item.issuer;
        }

        stage = 'username';

        if (created.username !== item.username) {
          await Totp.editUsername(created.id, item.username);
          username = item.username;
        }

        if (item.tags.length > 0) {
          stage = 'tags';
          await Totp.editTags(created.id, item.tags);
          report.withTags++;
        }

        if (item.pinned) {
          stage = 'pinned';
          await Totp.editPinned(created.id, true);
          report.withPinned++;
        }

        // 以校正后的目标值写入运行时（服务端响应可能仍是占位 issuer）
        const stored: IItem = {
          id: created.id,
          issuer: issuer,
          username: username,
          tags: [...item.tags],
          pinned: item.pinned,
          code: created.code,
          config: created.config
        };

        itemsRuntime.add(stored);
      } catch (e) {
        report.failed.push(new ImportFailure(item.issuer, item.username, stage, describeError(e as Object)));
      }

      onProgress(index + 1, total);
    }

    return report;
  }
}
