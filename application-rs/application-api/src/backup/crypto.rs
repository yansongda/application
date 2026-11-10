use crate::backup::envelope::{
    BackupCipher, BackupEnvelope, BackupItem, BackupKdf, BackupMeta, CIPHER_ALG, FORMAT, KDF_ALG,
    KDF_ITERATIONS, KIND, MAX_ITEMS, MAX_ITERATIONS, MIN_ITERATIONS, VERSION,
};
use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use application_kernel::result::{ErrorCode, Result};
use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use chrono::{DateTime, Local, SecondsFormat};
use pbkdf2::pbkdf2_hmac;
use sha2::Sha256;
use tracing::{error, warn};
use zeroize::Zeroize;

/// PBKDF2 salt 长度（字节）。
const SALT_LEN: usize = 16;
/// AES-GCM nonce 长度（字节）。
const NONCE_LEN: usize = 12;
/// PBKDF2 派生密钥长度（字节），即 AES-256 的密钥长度。
const KEY_LEN: usize = 32;
/// GCM 认证 tag 长度（字节）。
const TAG_LEN: usize = 16;
/// `data` 字段 base64 文本上限，防止解密前构造超大输入。
const MAX_DATA_LEN: usize = 512 * 1024;

/// 用生产参数（[`KDF_ITERATIONS`]）加密并生成 v1 信封。
pub fn encrypt(password: &str, items: &[BackupItem]) -> Result<BackupEnvelope> {
    if items.len() > MAX_ITEMS {
        return Err(ErrorCode::ParamsTotpBackupLimitExceeded);
    }

    let plaintext = serde_json::to_vec(items).map_err(|e| {
        error!("序列化备份条目失败: {:?}", e);

        ErrorCode::InternalCryptoFailed
    })?;
    let count = u32::try_from(items.len()).map_err(|_| ErrorCode::ParamsTotpBackupLimitExceeded)?;
    let created_at = Local::now().to_rfc3339_opts(SecondsFormat::Secs, false);

    seal(password, &plaintext, KDF_ITERATIONS, count, &created_at)
}

/// 校验信封头并解密出条目数组。
///
/// 头字段校验失败返回 `ParamsTotpBackupFormatInvalid`；密文认证失败统一返回
/// `ParamsTotpBackupPasswordInvalid`（不区分密码错误与数据损坏，避免给出爆破提示）。
pub fn decrypt(password: &str, envelope: &BackupEnvelope) -> Result<Vec<BackupItem>> {
    validate_envelope(envelope)?;

    decrypt_payload(password, envelope)
}

/// 信封头校验：格式/版本/算法/参数范围/时间/base64 长度。
fn validate_envelope(envelope: &BackupEnvelope) -> Result<()> {
    if envelope.format != FORMAT || envelope.kind != KIND || envelope.version != VERSION {
        return Err(ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    if envelope.kdf.alg != KDF_ALG || envelope.cipher.alg != CIPHER_ALG {
        return Err(ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    if !(MIN_ITERATIONS..=MAX_ITERATIONS).contains(&envelope.kdf.iterations) {
        return Err(ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    let count = usize::try_from(envelope.meta.count)
        .map_err(|_| ErrorCode::ParamsTotpBackupFormatInvalid)?;

    if count > MAX_ITEMS {
        return Err(ErrorCode::ParamsTotpBackupLimitExceeded);
    }

    DateTime::parse_from_rfc3339(&envelope.meta.created_at)
        .map_err(|_| ErrorCode::ParamsTotpBackupFormatInvalid)?;

    decode_fixed::<SALT_LEN>(&envelope.kdf.salt)?;
    decode_fixed::<NONCE_LEN>(&envelope.cipher.nonce)?;

    if envelope.data.len() > MAX_DATA_LEN {
        return Err(ErrorCode::ParamsTotpBackupLimitExceeded);
    }

    Ok(())
}

/// 解密并反序列化 payload；调用方需保证头字段已校验（或测试中主动绕过）。
fn decrypt_payload(password: &str, envelope: &BackupEnvelope) -> Result<Vec<BackupItem>> {
    let salt = decode_fixed::<SALT_LEN>(&envelope.kdf.salt)?;
    let nonce_bytes = decode_fixed::<NONCE_LEN>(&envelope.cipher.nonce)?;

    let mut ciphertext = STANDARD
        .decode(envelope.data.as_bytes())
        .map_err(|_| ErrorCode::ParamsTotpBackupFormatInvalid)?;

    if ciphertext.len() <= TAG_LEN {
        return Err(ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    let mut key = derive_key(password, &salt, envelope.kdf.iterations);
    let aad = envelope.aad();
    let cipher = Aes256Gcm::new_from_slice(&key).map_err(|_| ErrorCode::InternalCryptoFailed)?;
    let nonce = Nonce::from_slice(&nonce_bytes);
    let result = cipher.decrypt(
        nonce,
        Payload {
            msg: &ciphertext,
            aad: aad.as_bytes(),
        },
    );

    key.zeroize();
    ciphertext.zeroize();

    let mut plaintext = result.map_err(|e| {
        warn!("备份解密失败（密码错误或数据损坏）: {:?}", e);

        ErrorCode::ParamsTotpBackupPasswordInvalid
    })?;

    let items: Vec<BackupItem> = serde_json::from_slice(&plaintext).map_err(|e| {
        warn!("备份明文 payload 解析失败: {:?}", e);

        ErrorCode::ParamsTotpBackupFormatInvalid
    })?;

    plaintext.zeroize();

    let expected = usize::try_from(envelope.meta.count)
        .map_err(|_| ErrorCode::ParamsTotpBackupFormatInvalid)?;

    if items.len() != expected {
        return Err(ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    if items.len() > MAX_ITEMS {
        return Err(ErrorCode::ParamsTotpBackupLimitExceeded);
    }

    Ok(items)
}

/// 生成信封并用 AES-256-GCM 封装给定明文。
fn seal(
    password: &str,
    plaintext: &[u8],
    iterations: u32,
    count: u32,
    created_at: &str,
) -> Result<BackupEnvelope> {
    let mut salt = [0u8; SALT_LEN];
    let mut nonce_bytes = [0u8; NONCE_LEN];

    getrandom::getrandom(&mut salt).map_err(|e| {
        error!("生成备份 salt 失败: {:?}", e);

        ErrorCode::InternalCryptoFailed
    })?;
    getrandom::getrandom(&mut nonce_bytes).map_err(|e| {
        error!("生成备份 nonce 失败: {:?}", e);

        ErrorCode::InternalCryptoFailed
    })?;

    let mut envelope = BackupEnvelope {
        format: FORMAT.to_string(),
        kind: KIND.to_string(),
        version: VERSION,
        meta: BackupMeta {
            created_at: created_at.to_string(),
            count,
        },
        kdf: BackupKdf {
            alg: KDF_ALG.to_string(),
            iterations,
            salt: STANDARD.encode(salt),
        },
        cipher: BackupCipher {
            alg: CIPHER_ALG.to_string(),
            nonce: STANDARD.encode(nonce_bytes),
        },
        data: String::new(),
    };
    let aad = envelope.aad();

    let mut key = derive_key(password, &salt, iterations);
    let cipher = Aes256Gcm::new_from_slice(&key).map_err(|_| ErrorCode::InternalCryptoFailed)?;
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ciphertext = cipher
        .encrypt(
            nonce,
            Payload {
                msg: plaintext,
                aad: aad.as_bytes(),
            },
        )
        .map_err(|_| ErrorCode::InternalCryptoFailed)?;

    key.zeroize();
    salt.zeroize();

    envelope.data = STANDARD.encode(ciphertext);

    Ok(envelope)
}

/// PBKDF2-HMAC-SHA256 派生 32 字节密钥。
fn derive_key(password: &str, salt: &[u8], iterations: u32) -> [u8; KEY_LEN] {
    let mut key = [0u8; KEY_LEN];

    pbkdf2_hmac::<Sha256>(password.as_bytes(), salt, iterations, &mut key);

    key
}

/// 解码固定长度的 base64 字段（salt/nonce）。
fn decode_fixed<const N: usize>(encoded: &str) -> Result<[u8; N]> {
    let decoded = STANDARD
        .decode(encoded.as_bytes())
        .map_err(|_| ErrorCode::ParamsTotpBackupFormatInvalid)?;

    decoded
        .try_into()
        .map_err(|_| ErrorCode::ParamsTotpBackupFormatInvalid)
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::all,
        clippy::pedantic,
        clippy::unwrap_used,
        clippy::expect_used,
        clippy::panic
    )]

    use super::*;

    /// 测试用低迭代次数：debug 构建下 60 万次 PBKDF2 会让测试非常慢。
    const TEST_ITERATIONS: u32 = 1_000;

    fn sample_items() -> Vec<BackupItem> {
        vec![
            BackupItem {
                issuer: Some("GitHub".to_string()),
                username: "alice".to_string(),
                secret: "JBSWY3DPEHPK3PXP".to_string(),
                period: 30,
                digits: 6,
                algorithm: "SHA1".to_string(),
                tags: vec!["工作".to_string()],
                pinned: true,
                sort: 12,
            },
            BackupItem {
                issuer: None,
                username: "bob".to_string(),
                secret: "GEZDGNBVGY3TQOJQ".to_string(),
                period: 60,
                digits: 8,
                algorithm: "SHA256".to_string(),
                tags: Vec::new(),
                pinned: false,
                sort: 0,
            },
        ]
    }

    fn sample_envelope() -> BackupEnvelope {
        let items = sample_items();
        let plaintext = serde_json::to_vec(&items).unwrap();
        let count = u32::try_from(items.len()).unwrap();

        seal(
            "correct horse battery staple",
            &plaintext,
            TEST_ITERATIONS,
            count,
            "2026-06-28T14:30:00+08:00",
        )
        .unwrap()
    }

    /// 测试场景：正确密码 + 完整信封 → 验证条目原样还原 → 预期字段一致
    #[test]
    fn roundtrip_restores_items() {
        let envelope = sample_envelope();
        let items = decrypt_payload("correct horse battery staple", &envelope).unwrap();

        assert_eq!(items.len(), 2);
        assert_eq!(items[0].issuer.as_deref(), Some("GitHub"));
        assert_eq!(items[0].username, "alice");
        assert_eq!(items[0].secret, "JBSWY3DPEHPK3PXP");
        assert_eq!(items[0].digits, 6);
        assert_eq!(items[0].algorithm, "SHA1");
        assert_eq!(items[0].tags, vec!["工作".to_string()]);
        assert!(items[0].pinned);
        assert_eq!(items[0].sort, 12);
        assert_eq!(items[1].period, 60);
        assert_eq!(items[1].digits, 8);
    }

    /// 测试场景：错误密码 → 预期返回密码错误或数据损坏
    #[test]
    fn wrong_password_is_rejected() {
        let envelope = sample_envelope();
        let err = decrypt_payload("wrong password", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpBackupPasswordInvalid);
    }

    /// 测试场景：改动密文任意一个字节 → 预期 GCM 认证失败
    #[test]
    fn tampered_data_is_rejected() {
        let mut envelope = sample_envelope();
        let mut ciphertext = STANDARD.decode(envelope.data.as_bytes()).unwrap();
        let last = ciphertext.len() - 1;
        ciphertext[last] ^= 0x01;
        envelope.data = STANDARD.encode(ciphertext);

        let err = decrypt_payload("correct horse battery staple", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpBackupPasswordInvalid);
    }

    /// 测试场景：改动 `meta.count`（AAD 字段）→ 预期解密失败
    #[test]
    fn tampered_meta_count_is_rejected() {
        let mut envelope = sample_envelope();
        envelope.meta.count += 1;

        let err = decrypt_payload("correct horse battery staple", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpBackupPasswordInvalid);
    }

    /// 测试场景：改动 `meta.created_at`（AAD 字段）→ 预期解密失败
    #[test]
    fn tampered_meta_created_at_is_rejected() {
        let mut envelope = sample_envelope();
        envelope.meta.created_at = "2026-06-28T06:30:00Z".to_string();

        let err = decrypt_payload("correct horse battery staple", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpBackupPasswordInvalid);
    }

    /// 测试场景：改动 `kdf.iterations` → 派生密钥变化 → 预期解密失败
    #[test]
    fn tampered_iterations_is_rejected() {
        let mut envelope = sample_envelope();
        envelope.kdf.iterations += 1;

        let err = decrypt_payload("correct horse battery staple", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpBackupPasswordInvalid);
    }

    /// 测试场景：迭代次数低于导入下限 → 预期格式错误（不进入派生）
    #[test]
    fn validate_rejects_low_iterations() {
        let envelope = sample_envelope();
        let err = decrypt("correct horse battery staple", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    /// 测试场景：版本号不符 → 预期格式错误
    #[test]
    fn validate_rejects_unknown_version() {
        let mut envelope = sample_envelope();
        envelope.version = 2;

        let err = decrypt("correct horse battery staple", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    /// 测试场景：format/kind 不符 → 预期格式错误
    #[test]
    fn validate_rejects_wrong_format_and_kind() {
        let mut envelope = sample_envelope();
        envelope.format = "other".to_string();
        envelope.kind = "settings".to_string();

        let err = decrypt("correct horse battery staple", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    /// 测试场景：salt 长度不是 16 字节 → 预期格式错误
    #[test]
    fn validate_rejects_bad_salt_length() {
        let mut envelope = sample_envelope();
        envelope.kdf.salt = STANDARD.encode([0u8; 8]);

        let err = decrypt("correct horse battery staple", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    /// 测试场景：明文 payload 不是数组（对象）→ 预期格式错误
    #[test]
    fn payload_must_be_array() {
        let envelope = seal(
            "password",
            br#"{"items":[]}"#,
            TEST_ITERATIONS,
            0,
            "2026-06-28T14:30:00+08:00",
        )
        .unwrap();

        let err = decrypt_payload("password", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    /// 测试场景：`meta.count` 与明文数组长度不一致 → 预期格式错误
    #[test]
    fn payload_count_must_match_meta() {
        let envelope = seal(
            "password",
            b"[]",
            TEST_ITERATIONS,
            1,
            "2026-06-28T14:30:00+08:00",
        )
        .unwrap();

        let err = decrypt_payload("password", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    /// 测试场景：条目数超过上限 → 预期导出阶段即拒绝
    #[test]
    fn encrypt_rejects_too_many_items() {
        let items: Vec<BackupItem> = (0..=MAX_ITEMS)
            .map(|i| BackupItem {
                issuer: None,
                username: format!("user{i}"),
                secret: "JBSWY3DPEHPK3PXP".to_string(),
                period: 30,
                digits: 6,
                algorithm: "SHA1".to_string(),
                tags: Vec::new(),
                pinned: false,
                sort: 0,
            })
            .collect();

        let err = encrypt("password", &items).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpBackupLimitExceeded);
    }

    /// 测试场景：`created_at` 支持 `+08:00` 偏移与 `Z` → 预期头校验通过；缺少时区 → 预期格式错误
    #[test]
    fn validate_created_at_requires_timezone() {
        let mut envelope = sample_envelope();
        envelope.kdf.iterations = KDF_ITERATIONS;

        envelope.meta.created_at = "2026-06-28T06:30:00Z".to_string();
        assert!(validate_envelope(&envelope).is_ok());

        envelope.meta.created_at = "2026-06-28T14:30:00+08:00".to_string();
        assert!(validate_envelope(&envelope).is_ok());

        envelope.meta.created_at = "2026-06-28T14:30:00".to_string();
        assert_eq!(
            validate_envelope(&envelope).unwrap_err(),
            ErrorCode::ParamsTotpBackupFormatInvalid
        );
    }
}
