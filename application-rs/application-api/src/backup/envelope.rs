use serde::{Deserialize, Serialize};

/// 备份文件的格式标识：固定为 `application`，任何变更都需要提升 [`VERSION`]。
pub(crate) const FORMAT: &str = "application";
/// 备份内容类型：固定为 `totp`。
pub(crate) const KIND: &str = "totp";
/// 信封版本：字段、算法或 AAD 结构变更时 +1。
pub(crate) const VERSION: u32 = 1;
/// 单次备份允许的最大条目数（导出/导入共用）。
pub const MAX_ITEMS: usize = 50;

/// 密钥派生算法标识。
pub(crate) const KDF_ALG: &str = "pbkdf2-sha256";
/// 导出时使用的 PBKDF2 迭代次数。
pub(crate) const KDF_ITERATIONS: u32 = 600_000;
/// 导入时允许的迭代次数下限（防止构造超低强度的旧格式备份）。
pub(crate) const MIN_ITERATIONS: u32 = 100_000;
/// 导入时允许的迭代次数上限（防止构造超长迭代的备份拖垮 CPU）。
pub(crate) const MAX_ITERATIONS: u32 = 1_000_000;

/// 对称加密算法标识。
pub(crate) const CIPHER_ALG: &str = "aes-256-gcm";

/// 备份信封：头部字段参与 AAD 认证，`data` 为密文。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackupEnvelope {
    pub format: String,
    pub kind: String,
    pub version: u32,
    pub meta: BackupMeta,
    pub kdf: BackupKdf,
    pub cipher: BackupCipher,
    /// base64（标准字母表）编码的 `密文 || 16 字节 GCM tag`
    pub data: String,
}

impl BackupEnvelope {
    /// AAD（附加认证数据）：按固定顺序用 `\x1f` 拼接全部头字段。
    ///
    /// 任何头字段被篡改都会导致 AES-GCM 校验失败（表现为“密码错误或数据损坏”）。
    /// 该顺序与分隔符属于 v1 格式契约，变更必须提升 [`VERSION`]。
    pub fn aad(&self) -> String {
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
pub struct BackupMeta {
    /// 带时区偏移的 RFC3339 时间，例如 `2026-06-28T14:30:00+08:00`
    pub created_at: String,
    /// 条目数，解密后必须与 payload 数组长度一致
    pub count: u32,
}

/// 密钥派生参数。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackupKdf {
    pub alg: String,
    pub iterations: u32,
    /// base64（标准字母表）编码的 16 字节随机 salt
    pub salt: String,
}

/// 对称加密参数。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackupCipher {
    pub alg: String,
    /// base64（标准字母表）编码的 12 字节随机 nonce
    pub nonce: String,
}

/// 备份中的单条 TOTP 数据；字段与 `tool.totp` 的 `config` 语义保持一致。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackupItem {
    #[serde(default)]
    pub issuer: Option<String>,
    pub username: String,
    /// 大写、无填充的 base32 密钥
    pub secret: String,
    #[serde(default = "default_period")]
    pub period: u64,
    #[serde(default = "default_digits")]
    pub digits: u8,
    #[serde(default = "default_algorithm")]
    pub algorithm: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub pinned: bool,
    #[serde(default)]
    pub sort: u32,
}

fn default_period() -> u64 {
    30
}

fn default_digits() -> u8 {
    6
}

fn default_algorithm() -> String {
    "SHA1".to_string()
}

#[cfg(test)]
mod tests {
    #![allow(clippy::all)]

    use super::*;

    fn sample_envelope() -> BackupEnvelope {
        BackupEnvelope {
            format: FORMAT.to_string(),
            kind: KIND.to_string(),
            version: VERSION,
            meta: BackupMeta {
                created_at: "2026-06-28T14:30:00+08:00".to_string(),
                count: 1,
            },
            kdf: BackupKdf {
                alg: KDF_ALG.to_string(),
                iterations: KDF_ITERATIONS,
                salt: "c2FsdHNhbHRzYWx0c2FsdA==".to_string(),
            },
            cipher: BackupCipher {
                alg: CIPHER_ALG.to_string(),
                nonce: "bm9uY2Vub25jZQ==".to_string(),
            },
            data: "ZGF0YQ==".to_string(),
        }
    }

    /// 测试场景：固定信封 → 验证 AAD 字节序 → 预期与本文件文档中的 v1 契约一致
    #[test]
    fn aad_is_stable() {
        let envelope = sample_envelope();

        assert_eq!(
            envelope.aad(),
            "application\u{1f}totp\u{1f}1\u{1f}2026-06-28T14:30:00+08:00\u{1f}1\u{1f}\
             pbkdf2-sha256\u{1f}600000\u{1f}c2FsdHNhbHRzYWx0c2FsdA==\u{1f}\
             aes-256-gcm\u{1f}bm9uY2Vub25jZQ=="
        );
    }

    /// 测试场景：信封序列化 → 验证字段名 → 预期为规范中的 snake_case 字段
    #[test]
    fn envelope_serializes_expected_fields() {
        let json = serde_json::to_value(sample_envelope()).unwrap();

        assert_eq!(json["format"], "application");
        assert_eq!(json["kind"], "totp");
        assert_eq!(json["version"], 1);
        assert_eq!(json["meta"]["created_at"], "2026-06-28T14:30:00+08:00");
        assert_eq!(json["meta"]["count"], 1);
        assert_eq!(json["kdf"]["alg"], "pbkdf2-sha256");
        assert_eq!(json["kdf"]["iterations"], 600000);
        assert_eq!(json["cipher"]["alg"], "aes-256-gcm");
        assert_eq!(json["data"], "ZGF0YQ==");
    }

    /// 测试场景：条目缺省字段（手写/第三方备份）→ 验证 serde 默认值 → 预期 30/6/SHA1/空标签/未置顶/排序 0
    #[test]
    fn item_defaults_for_missing_optional_fields() {
        let item: BackupItem =
            serde_json::from_str(r#"{"username":"alice","secret":"JBSWY3DPEHPK3PXP"}"#).unwrap();

        assert_eq!(item.issuer, None);
        assert_eq!(item.period, 30);
        assert_eq!(item.digits, 6);
        assert_eq!(item.algorithm, "SHA1");
        assert!(item.tags.is_empty());
        assert!(!item.pinned);
        assert_eq!(item.sort, 0);
    }

    /// 测试场景：条目含未知字段（未来版本写入）→ 验证忽略 → 预期仍可反序列化
    #[test]
    fn item_ignores_unknown_fields() {
        let item: BackupItem = serde_json::from_str(
            r#"{"username":"alice","secret":"JBSWY3DPEHPK3PXP","future":true}"#,
        )
        .unwrap();

        assert_eq!(item.username, "alice");
    }
}
