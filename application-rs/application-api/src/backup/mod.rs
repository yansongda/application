//! TOTP 备份信封的编解码与加解密。
//!
//! 信封为 JSON，头部字段（`format`/`kind`/`version`/`meta`/`kdf`/`cipher`）全部参与
//! AAD 认证，`data` 为 base64 的标准编码密文（含 GCM tag）。明文 payload 为
//! [`BackupItem`] 数组，不含用户与数据库 id。

mod crypto;
mod envelope;

pub use crypto::{decrypt, encrypt};
pub use envelope::{BackupCipher, BackupEnvelope, BackupItem, BackupKdf, BackupMeta, MAX_ITEMS};
