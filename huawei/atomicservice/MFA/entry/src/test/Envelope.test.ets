import { describe, expect, it } from '@ohos/hypium';
import {
  decodeBase64Strict,
  encodeBase64,
  IEnvelope,
  parseEnvelope,
  stringifyEnvelope
} from '../main/ets/models/backup/Envelope';
import { BackupErrorCode } from '../main/ets/models/backup/Spec';

// 合法信封（与共享向量同结构的精简版：data 用 3 字节密文，避免测试内塞大字面量）
const EXAMPLE: string = '{"format":"mfa","version":1,"method":"PBKDF2-SHA256/AES-256-GCM",' +
  '"key":{"iterations":10000,"salt":"GdUxb0sazJpTZcEeCISwig==","iv":"IacMfU+gLiS/sa+E",' +
  '"tag":"TtJ6nXbg8Ql4ikSR94fSew==","kcv":"b8ZuT0hzVh0="},' +
  '"data":"AAAA",' +
  '"meta":{"count":0,"createdAt":"2026-11-07T00:00:00.000Z","source":"huawei","app":"1.9.0"}}';

function codeOf(text: string): string {
  const result = parseEnvelope(text);

  return result.ok ? 'OK' : result.code.toString();
}

// 用字符串替换构造非法变体（保持字段顺序稳定）
function mutate(search: string, replacement: string): string {
  return EXAMPLE.replace(search, replacement);
}

export default function envelopeTest(): void {
  describe('backupEnvelope', () => {
    it('parse_exampleSucceeds', 0, () => {
      const result = parseEnvelope(EXAMPLE);

      expect(result.ok).assertTrue();
      expect(result.envelope?.key.iterations).assertEqual(10000);
      expect(result.envelope?.meta.source).assertEqual('huawei');
    });

    it('parse_ignoresSurroundingWhitespace', 0, () => {
      expect(codeOf(`\n  ${EXAMPLE}\n`)).assertEqual('OK');
    });

    it('parse_unknownFieldsIgnored', 0, () => {
      const text = mutate('"format":"mfa"', '"format":"mfa","extra":{"x":1}');

      expect(codeOf(text)).assertEqual('OK');
    });

    it('stringify_roundTrips', 0, () => {
      const result = parseEnvelope(EXAMPLE);

      expect(result.ok).assertTrue();

      const envelope: IEnvelope = result.envelope as IEnvelope;

      expect(codeOf(stringifyEnvelope(envelope))).assertEqual('OK');
      expect(stringifyEnvelope(envelope).startsWith('{"format":"mfa","version":1,"method"')).assertTrue();
    });

    it('parse_nonJsonIsEFormat', 0, () => {
      expect(codeOf('not json')).assertEqual(BackupErrorCode.E_FORMAT.toString());
    });

    it('parse_wrongFormatIsEFormat', 0, () => {
      expect(codeOf(mutate('"format":"mfa"', '"format":"otpauth"'))).assertEqual(BackupErrorCode.E_FORMAT.toString());
    });

    it('parse_version2IsEVersion', 0, () => {
      expect(codeOf(mutate('"version":1', '"version":2'))).assertEqual(BackupErrorCode.E_VERSION.toString());
    });

    it('parse_versionNonIntegerOrBelowOneIsEStructure', 0, () => {
      expect(codeOf(mutate('"version":1', '"version":1.5'))).assertEqual(BackupErrorCode.E_STRUCTURE.toString());
      expect(codeOf(mutate('"version":1', '"version":0'))).assertEqual(BackupErrorCode.E_STRUCTURE.toString());
    });

    it('parse_unknownMethodIsEMethod', 0, () => {
      expect(codeOf(mutate('"method":"PBKDF2-SHA256/AES-256-GCM"', '"method":"PBKDF2-SHA256/AES-256-CBC"')))
        .assertEqual(BackupErrorCode.E_METHOD.toString());
    });

    it('parse_base64WhitespaceRejected', 0, () => {
      expect(codeOf(mutate('"GdUxb0sazJpTZcEeCISwig=="', '"GdUxb0sazJpTZcEeCISwig== "')))
        .assertEqual(BackupErrorCode.E_STRUCTURE.toString());
    });

    it('parse_base64UrlAlphabetRejected', 0, () => {
      expect(codeOf(mutate('"IacMfU+gLiS/sa+E"', '"IacMfU-gLiS_sa-E"')))
        .assertEqual(BackupErrorCode.E_STRUCTURE.toString());
    });

    it('parse_wrongKeyLengthIsEStructure', 0, () => {
      expect(codeOf(mutate('"b8ZuT0hzVh0="', '"b8ZuT0hzVh0="'))).assertEqual('OK');
      expect(codeOf(mutate('"b8ZuT0hzVh0="', '"b8ZuT0hzVg=="')))
        .assertEqual(BackupErrorCode.E_STRUCTURE.toString());
    });

    it('parse_iterationsOutOfRangeIsEStructure', 0, () => {
      expect(codeOf(mutate('"iterations":10000', '"iterations":9999')))
        .assertEqual(BackupErrorCode.E_STRUCTURE.toString());
      expect(codeOf(mutate('"iterations":10000', '"iterations":500001')))
        .assertEqual(BackupErrorCode.E_STRUCTURE.toString());
    });

    it('parse_emptyDataIsEStructure', 0, () => {
      expect(codeOf(mutate('"data":"AAAA"', '"data":""'))).assertEqual(BackupErrorCode.E_STRUCTURE.toString());
    });

    it('parse_createdAtMustEndWithZ', 0, () => {
      expect(codeOf(mutate('"createdAt":"2026-11-07T00:00:00.000Z"',
        '"createdAt":"2026-11-07T00:00:00+00:00"'))).assertEqual(BackupErrorCode.E_STRUCTURE.toString());
      expect(codeOf(mutate('"createdAt":"2026-11-07T00:00:00.000Z"',
        '"createdAt":"2026-11-07T00:00:00Z"'))).assertEqual('OK');
    });

    it('parse_sourceAndCountValidation', 0, () => {
      expect(codeOf(mutate('"source":"huawei"', '"source":"google"')))
        .assertEqual(BackupErrorCode.E_STRUCTURE.toString());
      expect(codeOf(mutate('"count":0', '"count":501')))
        .assertEqual(BackupErrorCode.E_STRUCTURE.toString());
    });

    it('parse_appLengthLimit', 0, () => {
      const longApp: string = 'x'.repeat(33);

      expect(codeOf(mutate('"app":"1.9.0"', `"app":"${longApp}"`)))
        .assertEqual(BackupErrorCode.E_STRUCTURE.toString());
    });

    it('base64_roundTrips', 0, () => {
      const bytes: Uint8Array = new Uint8Array([0, 1, 2, 250, 255]);

      expect(encodeBase64(bytes)).assertEqual('AAEC+v8=');
      expect(encodeBase64(decodeBase64Strict('AAEC+v8='))).assertEqual('AAEC+v8=');
    });

    it('base64_rejectsNonMultipleOfFour', 0, () => {
      let thrown: string = '';

      try {
        decodeBase64Strict('AAA');
      } catch (e) {
        thrown = 'E_STRUCTURE';
      }

      expect(thrown).assertEqual('E_STRUCTURE');
    });
  });
}
