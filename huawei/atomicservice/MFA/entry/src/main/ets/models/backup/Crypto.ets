// 备份加解密（华为原生 cryptoFramework）：PBKDF2-SHA256 / AES-256-GCM / HMAC-SHA256 kcv。
// 判定顺序（规范 §4.4）：kcv 先于 GCM —— 口令错误与文件损坏必须给出不同错误码。
// 口令/密钥/明文/密文只在内存中存在，禁止写入日志或 preferences。
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { BackupError, BackupErrorCode, BackupSpec } from './Spec';

export interface IEncryptResult {
  ciphertext: Uint8Array;
  tag: Uint8Array;
}

export class BackupCrypto {
  // 规范 §5：trim → NFC；运行时缺少 normalize 必须 fail-closed（禁止降级为不归一化）
  static normalizePassword(password: string): string {
    if ('function' !== typeof password.normalize) {
      throw new BackupError(BackupErrorCode.E_NORMALIZE, 'String.prototype.normalize 不可用');
    }

    return password.trim().normalize('NFC');
  }

  static utf8Bytes(text: string): Uint8Array {
    return new util.TextEncoder().encodeInto(text);
  }

  static utf8Text(bytes: Uint8Array): string {
    return new util.TextDecoder().decodeToString(bytes);
  }

  // 按 Unicode 码点计数（规范 §5：两端都不得用 UTF-16 .length 判强度）
  static codePointLength(text: string): number {
    let count: number = 0;

    for (let i = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i);

      if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
        const next: number = text.charCodeAt(i + 1);

        if (next >= 0xdc00 && next <= 0xdfff) {
          i++;
        }
      }

      count++;
    }

    return count;
  }

  // 导出端强度校验：不足 8 码点或命中弱口令表时返回提示文案
  static checkPassword(password: string): string | undefined {
    const normalized: string = BackupCrypto.normalizePassword(password);

    if (BackupCrypto.codePointLength(normalized) < BackupSpec.MIN_PASSWORD_CODE_POINTS) {
      return `口令至少 ${BackupSpec.MIN_PASSWORD_CODE_POINTS} 个字符`;
    }

    if (BackupSpec.WEAK_PASSWORDS.includes(normalized)) {
      return '口令过弱，请换一个';
    }

    return undefined;
  }

  static async deriveKey(password: string, salt: Uint8Array, iterations: number): Promise<Uint8Array> {
    const kdf: cryptoFramework.Kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: BackupCrypto.utf8Bytes(BackupCrypto.normalizePassword(password)),
      salt: salt,
      iterations: iterations,
      keySize: BackupSpec.KEY_BYTES
    };
    const secret: cryptoFramework.DataBlob = await kdf.generateSecret(spec);

    return secret.data;
  }

  // kcv = HMAC-SHA256(key, "mfa-kcv|1") 的前 8 字节（规范 §4.1）
  static async kcv(key: Uint8Array): Promise<Uint8Array> {
    const mac: cryptoFramework.Mac = cryptoFramework.createMac('SHA256');
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC|SHA256');
    const symKey: cryptoFramework.SymKey = await generator.convertKey({ data: key });

    await mac.init(symKey);
    await mac.update({ data: BackupCrypto.utf8Bytes(BackupSpec.KCV_LABEL) });

    const digest: cryptoFramework.DataBlob = await mac.doFinal();

    return digest.data.subarray(0, BackupSpec.KCV_BYTES);
  }

  static async encrypt(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    plaintext: Uint8Array): Promise<IEncryptResult> {
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
    const symKey: cryptoFramework.SymKey = await generator.convertKey({ data: key });
    const params: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: iv },
      aad: { data: aad },
      authTag: { data: new Uint8Array(BackupSpec.TAG_BYTES) }
    };

    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);

    const output: cryptoFramework.DataBlob = await cipher.doFinal({ data: plaintext });
    const splitIndex: number = output.data.length - BackupSpec.TAG_BYTES;

    if (splitIndex < 0) {
      throw new BackupError(BackupErrorCode.E_CORRUPT, 'GCM 输出长度异常');
    }

    const result: IEncryptResult = {
      ciphertext: output.data.subarray(0, splitIndex),
      tag: output.data.subarray(splitIndex)
    };

    return result;
  }

  // 解密失败（tag 校验不过）返回 undefined，由调用方映射 E_CORRUPT
  static async decrypt(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    ciphertext: Uint8Array, tag: Uint8Array): Promise<Uint8Array | undefined> {
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
    const symKey: cryptoFramework.SymKey = await generator.convertKey({ data: key });
    const params: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: iv },
      aad: { data: aad },
      authTag: { data: tag }
    };

    try {
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);

      const output: cryptoFramework.DataBlob = await cipher.doFinal({ data: ciphertext });

      return output.data;
    } catch (e) {
      return undefined;
    }
  }

  // CSPRNG（规范 §4.1：salt/iv 必须来自密码学安全随机源）
  static randomBytes(length: number): Uint8Array {
    const random: cryptoFramework.Random = cryptoFramework.createRandom();
    const blob: cryptoFramework.DataBlob = random.generateRandomSync(length);

    return blob.data;
  }
}
