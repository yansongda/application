use crate::request::Validator;
use application_kernel::result::ErrorCode;
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// 导出备份的密码最小长度（导入只校验上限，保证旧备份兼容）。
const MIN_BACKUP_PASSWORD_CHARS: usize = 8;
/// 备份密码的最大字符数。
const MAX_BACKUP_PASSWORD_CHARS: usize = 128;
/// 备份类型标识的最大字符数。
const MAX_KIND_CHARS: usize = 32;

#[derive(Debug, Clone, Deserialize)]
pub struct ExportRequest {
    pub kind: Option<String>,
    pub password: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ExportParams {
    pub kind: String,
    pub password: String,
}

impl Validator for ExportRequest {
    type Data = ExportParams;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let kind = self
            .kind
            .as_deref()
            .filter(|kind| !kind.is_empty() && kind.chars().count() <= MAX_KIND_CHARS)
            .ok_or(ErrorCode::ParamsBackupKindUnsupported)?
            .to_string();
        let password = self
            .password
            .as_deref()
            .ok_or(ErrorCode::ParamsBackupPasswordFormatInvalid)?;

        let count = password.chars().count();

        if !(MIN_BACKUP_PASSWORD_CHARS..=MAX_BACKUP_PASSWORD_CHARS).contains(&count) {
            return Err(ErrorCode::ParamsBackupPasswordFormatInvalid);
        }

        Ok(ExportParams {
            kind,
            password: password.to_string(),
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct ImportRequest {
    pub kind: Option<String>,
    pub password: Option<String>,
    pub backup: Option<Value>,
}

#[derive(Debug, Clone)]
pub struct ImportParams {
    pub kind: String,
    pub password: String,
    pub backup: Value,
}

impl Validator for ImportRequest {
    type Data = ImportParams;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let kind = self
            .kind
            .as_deref()
            .filter(|kind| !kind.is_empty() && kind.chars().count() <= MAX_KIND_CHARS)
            .ok_or(ErrorCode::ParamsBackupKindUnsupported)?
            .to_string();
        let password = self
            .password
            .as_deref()
            .ok_or(ErrorCode::ParamsBackupPasswordFormatInvalid)?;

        // 导入只校验上限：未来提高导出门槛后，旧备份仍能导入
        if password.is_empty() || password.chars().count() > MAX_BACKUP_PASSWORD_CHARS {
            return Err(ErrorCode::ParamsBackupPasswordFormatInvalid);
        }

        let backup = self
            .backup
            .as_ref()
            .ok_or(ErrorCode::ParamsBackupFormatInvalid)?;

        if !backup.is_object() {
            return Err(ErrorCode::ParamsBackupFormatInvalid);
        }

        Ok(ImportParams {
            kind,
            password: password.to_string(),
            backup: backup.clone(),
        })
    }
}

#[derive(Debug, Serialize)]
pub struct ImportResponse {
    pub imported: u32,
}

#[cfg(test)]
mod tests {
    #![allow(clippy::all)]

    use super::*;

    /// 测试场景：缺少 `kind` → 预期类型不支持
    #[test]
    fn export_requires_kind() {
        let request: ExportRequest = serde_json::from_str(r#"{"password":"12345678"}"#).unwrap();

        assert_eq!(
            request.validate().unwrap_err(),
            ErrorCode::ParamsBackupKindUnsupported
        );
    }

    /// 测试场景：`kind` 为空串 → 预期类型不支持
    #[test]
    fn export_rejects_empty_kind() {
        let request: ExportRequest =
            serde_json::from_str(r#"{"kind":"","password":"12345678"}"#).unwrap();

        assert_eq!(
            request.validate().unwrap_err(),
            ErrorCode::ParamsBackupKindUnsupported
        );
    }

    /// 测试场景：备份密码少于 8 位 → 预期密码格式错误
    #[test]
    fn export_rejects_short_password() {
        let request: ExportRequest =
            serde_json::from_str(r#"{"kind":"totp","password":"1234567"}"#).unwrap();

        assert_eq!(
            request.validate().unwrap_err(),
            ErrorCode::ParamsBackupPasswordFormatInvalid
        );
    }

    /// 测试场景：密码 8 位 → 预期校验通过并原样返回 kind/password
    #[test]
    fn export_accepts_min_length_password() {
        let request: ExportRequest =
            serde_json::from_str(r#"{"kind":"totp","password":"12345678"}"#).unwrap();
        let params = request.validate().unwrap();

        assert_eq!(params.kind, "totp");
        assert_eq!(params.password, "12345678");
    }

    /// 测试场景：导入密码只有 1 位（旧备份兼容）→ 预期校验通过
    #[test]
    fn import_accepts_short_password() {
        let request: ImportRequest = serde_json::from_str(
            r#"{"kind":"totp","password":"x","backup":{"format":"application"}}"#,
        )
        .unwrap();

        assert!(request.validate().is_ok());
    }

    /// 测试场景：导入密码为空 → 预期密码格式错误
    #[test]
    fn import_rejects_empty_password() {
        let request: ImportRequest = serde_json::from_str(
            r#"{"kind":"totp","password":"","backup":{"format":"application"}}"#,
        )
        .unwrap();

        assert_eq!(
            request.validate().unwrap_err(),
            ErrorCode::ParamsBackupPasswordFormatInvalid
        );
    }

    /// 测试场景：缺少 `kind` → 预期类型不支持
    #[test]
    fn import_requires_kind() {
        let request: ImportRequest =
            serde_json::from_str(r#"{"password":"12345678","backup":{}}"#).unwrap();

        assert_eq!(
            request.validate().unwrap_err(),
            ErrorCode::ParamsBackupKindUnsupported
        );
    }

    /// 测试场景：`backup` 缺失 → 预期备份格式错误
    #[test]
    fn import_requires_backup() {
        let request: ImportRequest =
            serde_json::from_str(r#"{"kind":"totp","password":"12345678"}"#).unwrap();

        assert_eq!(
            request.validate().unwrap_err(),
            ErrorCode::ParamsBackupFormatInvalid
        );
    }

    /// 测试场景：`backup` 不是对象（字符串/数组）→ 预期备份格式错误
    #[test]
    fn import_requires_backup_object() {
        let request: ImportRequest =
            serde_json::from_str(r#"{"kind":"totp","password":"12345678","backup":"text"}"#)
                .unwrap();

        assert_eq!(
            request.validate().unwrap_err(),
            ErrorCode::ParamsBackupFormatInvalid
        );
    }
}
