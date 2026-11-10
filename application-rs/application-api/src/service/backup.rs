//! 通用加密备份：信封编解码、PBKDF2 + AES-256-GCM 加解密与按 `kind` 分发。
//!
//! 具体备份类型（如 `totp`）只需在自己的模块中定义条目结构并实现 [`Item`]：
//!
//! - [`create`] / [`decrypt`] 负责信封构造、AAD、加解密与逐条校验；
//! - [`export`] / [`import`] 是按 `kind` 分发的注册入口，新增类型时在此追加分支。

use crate::service::totp;
use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use application_database::account::access_token;
use application_kernel::result::{ErrorCode, Result};
use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use chrono::{DateTime, Local, SecondsFormat};
use pbkdf2::pbkdf2_hmac;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::Sha256;
use tracing::{error, warn};
use zeroize::Zeroizing;

/// 备份文件的格式标识，任何变更都需要提升 [`VERSION`]。
const FORMAT: &str = "application";
/// 信封版本：字段、算法或 AAD 结构变更时 +1。
const VERSION: u32 = 1;
/// 单类备份允许的最大条目数（导出/导入共用）。
const MAX_ITEMS: usize = 50;

/// 密钥派生算法标识。
const KDF_ALG: &str = "pbkdf2-sha256";
/// 导出时使用的 PBKDF2 迭代次数。
const KDF_ITERATIONS: u32 = 600_000;
/// 导入时允许的迭代次数下限（防止构造超低强度的旧格式备份）。
const MIN_ITERATIONS: u32 = 100_000;
/// 导入时允许的迭代次数上限（防止构造超长迭代的备份拖垮 CPU）。
const MAX_ITERATIONS: u32 = 1_000_000;

/// 对称加密算法标识。
const CIPHER_ALG: &str = "aes-256-gcm";

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

/// 备份载荷条目契约：每种 `kind` 的条目类型实现本 trait 即可复用信封/加解密/校验流程。
pub trait Item: Serialize + DeserializeOwned + Sized {
    /// 该条目类型对应的信封 `kind`（如 `totp`）。
    const KIND: &'static str;

    /// 校验并归一化单条数据；解密后逐条调用，失败时由实现方返回合适的错误码（通常为 `ParamsBackupFormatInvalid`）。
    fn validate(self) -> Result<Self>;
}

/// 备份信封：头部字段参与 AAD 认证，`data` 为密文。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Envelope {
    pub format: String,
    pub kind: String,
    pub version: u32,
    pub meta: Meta,
    pub kdf: Kdf,
    pub cipher: Cipher,
    /// base64（标准字母表）编码的 `密文 || 16 字节 GCM tag`
    pub data: String,
}

impl Envelope {
    /// AAD：按固定顺序用 `\x1f` 拼接全部头字段。
    ///
    /// 任何头字段被篡改都会导致 AES-GCM 校验失败（表现为“密码错误或数据损坏”）。
    /// 该顺序与分隔符属于 v1 格式契约，变更必须提升 [`VERSION`]。
    fn aad(&self) -> String {
        format!(
            "{}\u{1f}{}\u{1f}{}\u{1f}{}\u{1f}{}\u{1f}{}\u{1f}{}\u{1f}{}\u{1f}{}\u{1f}{}",
            self.format,
            self.kind,
            self.version,
            self.meta.created_at,
            self.meta.count,
            self.kdf.alg,
            self.kdf.iterations,
            self.kdf.salt,
            self.cipher.alg,
            self.cipher.nonce,
        )
    }
}

/// 明文可见的元信息：用于导入前的展示与解密后的条数校验。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Meta {
    /// 带时区偏移的 RFC3339 时间，例如 `2026-06-28T14:30:00+08:00`
    pub created_at: String,
    /// 条目数，解密后必须与 payload 数组长度一致
    pub count: u32,
}

/// 密钥派生参数。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Kdf {
    pub alg: String,
    pub iterations: u32,
    /// base64（标准字母表）编码的 16 字节随机 salt
    pub salt: String,
}

/// 对称加密参数。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Cipher {
    pub alg: String,
    /// base64（标准字母表）编码的 12 字节随机 nonce
    pub nonce: String,
}

/// 按 `kind` 分发导出：新增备份类型时在此追加分支。
pub async fn export(
    access_token: &access_token::AccessToken,
    kind: &str,
    password: String,
) -> Result<Envelope> {
    if kind == totp::BACKUP_KIND_TOTP {
        return totp::backup_export(access_token, password).await;
    }

    Err(ErrorCode::ParamsBackupKindUnsupported)
}

/// 按 `kind` 分发导入：新增备份类型时在此追加分支。
pub async fn import(
    access_token: &access_token::AccessToken,
    kind: &str,
    password: String,
    backup: Value,
) -> Result<u32> {
    if kind == totp::BACKUP_KIND_TOTP {
        return totp::backup_import(access_token, password, backup).await;
    }

    Err(ErrorCode::ParamsBackupKindUnsupported)
}

/// 用生产参数（`KDF_ITERATIONS`）加密并生成 v1 信封；`kind` 取自 [`Item::KIND`]。
pub fn create<P: Item>(password: &str, items: &[P]) -> Result<Envelope> {
    if items.len() > MAX_ITEMS {
        return Err(ErrorCode::ParamsBackupLimitExceeded);
    }

    let plaintext = Zeroizing::new(serde_json::to_vec(items).map_err(|e| {
        error!("序列化备份条目失败: {:?}", e);

        ErrorCode::InternalCryptoFailed
    })?);
    let count = u32::try_from(items.len()).map_err(|_| ErrorCode::ParamsBackupLimitExceeded)?;

    create_with::<P>(password, plaintext.as_slice(), count, KDF_ITERATIONS)
}

/// 校验信封头并解密为条目数组；`kind` 必须与 [`Item::KIND`] 一致。
///
/// 头字段校验失败返回 `ParamsBackupFormatInvalid`；密文认证失败统一返回
/// `ParamsBackupPasswordInvalid`（不区分密码错误与数据损坏，避免给出爆破提示）。
pub fn decrypt<P: Item>(password: &str, envelope: &Envelope) -> Result<Vec<P>> {
    if envelope.kind != P::KIND {
        return Err(ErrorCode::ParamsBackupFormatInvalid);
    }

    validate_envelope(envelope)?;

    decrypt_payload::<P>(password, envelope)
}

/// 信封头校验：格式/版本/算法/参数范围/时间/base64 长度。
fn validate_envelope(envelope: &Envelope) -> Result<()> {
    if envelope.format != FORMAT || envelope.version != VERSION {
        return Err(ErrorCode::ParamsBackupFormatInvalid);
    }

    if envelope.kdf.alg != KDF_ALG || envelope.cipher.alg != CIPHER_ALG {
        return Err(ErrorCode::ParamsBackupFormatInvalid);
    }

    if !(MIN_ITERATIONS..=MAX_ITERATIONS).contains(&envelope.kdf.iterations) {
        return Err(ErrorCode::ParamsBackupFormatInvalid);
    }

    let count =
        usize::try_from(envelope.meta.count).map_err(|_| ErrorCode::ParamsBackupFormatInvalid)?;

    if count > MAX_ITEMS {
        return Err(ErrorCode::ParamsBackupLimitExceeded);
    }

    DateTime::parse_from_rfc3339(&envelope.meta.created_at)
        .map_err(|_| ErrorCode::ParamsBackupFormatInvalid)?;

    decode_fixed::<SALT_LEN>(&envelope.kdf.salt)?;
    decode_fixed::<NONCE_LEN>(&envelope.cipher.nonce)?;

    if envelope.data.len() > MAX_DATA_LEN {
        return Err(ErrorCode::ParamsBackupFormatInvalid);
    }

    Ok(())
}

/// 解密、反序列化并逐条校验 payload；调用方需保证信封头已校验（或测试中主动绕过）。
fn decrypt_payload<P: Item>(password: &str, envelope: &Envelope) -> Result<Vec<P>> {
    let salt = decode_fixed::<SALT_LEN>(&envelope.kdf.salt)?;
    let nonce_bytes = decode_fixed::<NONCE_LEN>(&envelope.cipher.nonce)?;

    let ciphertext = STANDARD
        .decode(envelope.data.as_bytes())
        .map_err(|_| ErrorCode::ParamsBackupFormatInvalid)?;

    if ciphertext.len() <= TAG_LEN {
        return Err(ErrorCode::ParamsBackupFormatInvalid);
    }

    let key = Zeroizing::new(derive_key(password, &salt, envelope.kdf.iterations));
    let aad = envelope.aad();
    let cipher =
        Aes256Gcm::new_from_slice(&key[..]).map_err(|_| ErrorCode::InternalCryptoFailed)?;
    let nonce = Nonce::from_slice(&nonce_bytes);
    let result = cipher.decrypt(
        nonce,
        Payload {
            msg: &ciphertext,
            aad: aad.as_bytes(),
        },
    );

    let plaintext = Zeroizing::new(result.map_err(|e| {
        warn!("备份解密失败（密码错误或数据损坏）: {:?}", e);

        ErrorCode::ParamsBackupPasswordInvalid
    })?);

    let items: Vec<P> = serde_json::from_slice(plaintext.as_slice()).map_err(|e| {
        warn!("备份明文 payload 解析失败: {:?}", e);

        ErrorCode::ParamsBackupFormatInvalid
    })?;

    let expected =
        usize::try_from(envelope.meta.count).map_err(|_| ErrorCode::ParamsBackupFormatInvalid)?;

    if items.len() != expected {
        return Err(ErrorCode::ParamsBackupFormatInvalid);
    }

    items.into_iter().map(Item::validate).collect()
}

/// 生成信封并用 AES-256-GCM 封装给定明文；`kind` 取 `P::KIND`。
/// `iterations` 仅供测试使用低迭代参数，生产入口 [`create`] 固定传 [`KDF_ITERATIONS`]。
fn create_with<P: Item>(
    password: &str,
    plaintext: &[u8],
    count: u32,
    iterations: u32,
) -> Result<Envelope> {
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

    let mut envelope = Envelope {
        format: FORMAT.to_string(),
        kind: P::KIND.to_string(),
        version: VERSION,
        meta: Meta {
            created_at: Local::now().to_rfc3339_opts(SecondsFormat::Secs, false),
            count,
        },
        kdf: Kdf {
            alg: KDF_ALG.to_string(),
            iterations,
            salt: STANDARD.encode(salt),
        },
        cipher: Cipher {
            alg: CIPHER_ALG.to_string(),
            nonce: STANDARD.encode(nonce_bytes),
        },
        data: String::new(),
    };
    let aad = envelope.aad();

    let key = Zeroizing::new(derive_key(password, &salt, iterations));
    let cipher =
        Aes256Gcm::new_from_slice(&key[..]).map_err(|_| ErrorCode::InternalCryptoFailed)?;
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
        .map_err(|_| ErrorCode::ParamsBackupFormatInvalid)?;

    decoded
        .try_into()
        .map_err(|_| ErrorCode::ParamsBackupFormatInvalid)
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
    const TEST_CREATED_AT: &str = "2026-06-28T14:30:00+08:00";

    /// 与具体业务无关的测试条目，验证 trait 抽象可复用。
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    struct TestItem {
        name: String,
    }

    impl Item for TestItem {
        const KIND: &'static str = "test";

        fn validate(self) -> Result<Self> {
            if self.name.is_empty() {
                return Err(ErrorCode::ParamsBackupFormatInvalid);
            }

            Ok(self)
        }
    }

    fn sample_items() -> Vec<TestItem> {
        vec![
            TestItem {
                name: "alice".to_string(),
            },
            TestItem {
                name: "bob".to_string(),
            },
        ]
    }

    fn sample_envelope() -> Envelope {
        let items = sample_items();
        let plaintext = serde_json::to_vec(&items).unwrap();
        let count = u32::try_from(items.len()).unwrap();

        create_with::<TestItem>(
            "correct horse battery staple",
            plaintext.as_slice(),
            count,
            TEST_ITERATIONS,
        )
        .unwrap()
    }

    /// 固定字段的信封：只用于锁定 AAD 字节序，不参与加解密。
    fn fixed_envelope() -> Envelope {
        Envelope {
            format: FORMAT.to_string(),
            kind: TestItem::KIND.to_string(),
            version: VERSION,
            meta: Meta {
                created_at: TEST_CREATED_AT.to_string(),
                count: 2,
            },
            kdf: Kdf {
                alg: KDF_ALG.to_string(),
                iterations: KDF_ITERATIONS,
                salt: "AAAAAAAAAAAAAAAAAAAAAA==".to_string(),
            },
            cipher: Cipher {
                alg: CIPHER_ALG.to_string(),
                nonce: "AAAAAAAAAAAAAAAA".to_string(),
            },
            data: "ZGF0YQ==".to_string(),
        }
    }

    /// 测试场景：固定信封 → 验证 AAD 字节序 → 预期与本模块文档中的 v1 契约一致
    #[test]
    fn aad_is_stable() {
        let envelope = fixed_envelope();

        assert_eq!(
            envelope.aad(),
            "application\u{1f}test\u{1f}1\u{1f}2026-06-28T14:30:00+08:00\u{1f}2\u{1f}\
             pbkdf2-sha256\u{1f}600000\u{1f}AAAAAAAAAAAAAAAAAAAAAA==\u{1f}\
             aes-256-gcm\u{1f}AAAAAAAAAAAAAAAA"
        );
    }

    /// 测试场景：信封序列化 → 验证字段名 → 预期为规范中的 snake_case 字段
    #[test]
    fn envelope_serializes_expected_fields() {
        let json = serde_json::to_value(sample_envelope()).unwrap();

        assert_eq!(json["format"], "application");
        assert_eq!(json["kind"], "test");
        assert_eq!(json["version"], 1);
        assert!(json["meta"]["created_at"].is_string());
        assert_eq!(json["meta"]["count"], 2);
        assert_eq!(json["kdf"]["alg"], "pbkdf2-sha256");
        assert_eq!(json["cipher"]["alg"], "aes-256-gcm");
    }

    /// 测试场景：正确密码 + 完整信封 → 验证条目原样还原 → 预期字段一致
    #[test]
    fn roundtrip_restores_items() {
        let envelope = sample_envelope();
        let items = decrypt_payload::<TestItem>("correct horse battery staple", &envelope).unwrap();

        assert_eq!(items, sample_items());
    }

    /// 测试场景：错误密码 → 预期返回密码错误或数据损坏
    #[test]
    fn wrong_password_is_rejected() {
        let envelope = sample_envelope();
        let err = decrypt_payload::<TestItem>("wrong password", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupPasswordInvalid);
    }

    /// 测试场景：改动密文任意一个字节 → 预期 GCM 认证失败
    #[test]
    fn tampered_data_is_rejected() {
        let mut envelope = sample_envelope();
        let mut ciphertext = STANDARD.decode(envelope.data.as_bytes()).unwrap();
        let last = ciphertext.len() - 1;
        ciphertext[last] ^= 0x01;
        envelope.data = STANDARD.encode(ciphertext);

        let err =
            decrypt_payload::<TestItem>("correct horse battery staple", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupPasswordInvalid);
    }

    /// 测试场景：改动 `meta.count`（AAD 字段）→ 预期解密失败
    #[test]
    fn tampered_meta_count_is_rejected() {
        let mut envelope = sample_envelope();
        envelope.meta.count += 1;

        let err =
            decrypt_payload::<TestItem>("correct horse battery staple", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupPasswordInvalid);
    }

    /// 测试场景：改动 `meta.created_at`（AAD 字段）→ 预期解密失败
    #[test]
    fn tampered_meta_created_at_is_rejected() {
        let mut envelope = sample_envelope();
        envelope.meta.created_at = "2026-06-28T06:30:00Z".to_string();

        let err =
            decrypt_payload::<TestItem>("correct horse battery staple", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupPasswordInvalid);
    }

    /// 测试场景：改动 `kdf.iterations` → 派生密钥变化 → 预期解密失败
    #[test]
    fn tampered_iterations_is_rejected() {
        let mut envelope = sample_envelope();
        envelope.kdf.iterations += 1;

        let err =
            decrypt_payload::<TestItem>("correct horse battery staple", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupPasswordInvalid);
    }

    /// 测试场景：信封 `kind` 与条目类型不一致 → 预期格式错误（不进入派生）
    #[test]
    fn kind_mismatch_is_rejected() {
        let mut envelope = sample_envelope();
        envelope.kind = "other".to_string();

        let err = decrypt::<TestItem>("password", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupFormatInvalid);
    }

    /// 测试场景：迭代次数低于导入下限 → 预期格式错误（不进入派生）
    #[test]
    fn validate_rejects_low_iterations() {
        let envelope = sample_envelope();
        let err = decrypt::<TestItem>("correct horse battery staple", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupFormatInvalid);
    }

    /// 测试场景：版本号不符 → 预期格式错误
    #[test]
    fn validate_rejects_unknown_version() {
        let mut envelope = sample_envelope();
        envelope.version = 2;

        let err = validate_envelope(&envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupFormatInvalid);
    }

    /// 测试场景：format 不符 → 预期格式错误
    #[test]
    fn validate_rejects_wrong_format() {
        let mut envelope = sample_envelope();
        envelope.format = "other".to_string();

        let err = validate_envelope(&envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupFormatInvalid);
    }

    /// 测试场景：salt 长度不是 16 字节 → 预期格式错误
    #[test]
    fn validate_rejects_bad_salt_length() {
        let mut envelope = sample_envelope();
        envelope.kdf.salt = STANDARD.encode([0u8; 8]);

        let err = validate_envelope(&envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupFormatInvalid);
    }

    /// 测试场景：明文 payload 不是数组（对象）→ 预期格式错误
    #[test]
    fn payload_must_be_array() {
        let envelope =
            create_with::<TestItem>("password", br#"{"items":[]}"#, 0, TEST_ITERATIONS).unwrap();

        let err = decrypt_payload::<TestItem>("password", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupFormatInvalid);
    }

    /// 测试场景：`meta.count` 与明文数组长度不一致 → 预期格式错误
    #[test]
    fn payload_count_must_match_meta() {
        let envelope = create_with::<TestItem>("password", b"[]", 1, TEST_ITERATIONS).unwrap();

        let err = decrypt_payload::<TestItem>("password", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupFormatInvalid);
    }

    /// 测试场景：条目自身校验失败 → 预期返回实现方错误码
    #[test]
    fn item_validation_is_applied() {
        let items = vec![TestItem {
            name: String::new(),
        }];
        let plaintext = serde_json::to_vec(&items).unwrap();
        let envelope =
            create_with::<TestItem>("password", plaintext.as_slice(), 1, TEST_ITERATIONS).unwrap();

        let err = decrypt_payload::<TestItem>("password", &envelope).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupFormatInvalid);
    }

    /// 测试场景：条目数超过上限 → 预期导出阶段即拒绝
    #[test]
    fn seal_rejects_too_many_items() {
        let items: Vec<TestItem> = (0..=MAX_ITEMS)
            .map(|i| TestItem {
                name: format!("user{i}"),
            })
            .collect();

        let err = create("password", &items).unwrap_err();

        assert_eq!(err, ErrorCode::ParamsBackupLimitExceeded);
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
            ErrorCode::ParamsBackupFormatInvalid
        );
    }
}
