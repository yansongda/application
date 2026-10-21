use crate::request::Validator;
use application_database::account::user::{Config, User};
use application_kernel::result::ErrorCode;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize)]
pub struct EditAvatarRequest {
    pub avatar: Option<String>,
}

impl Validator for EditAvatarRequest {
    type Data = String;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let avatar = self
            .avatar
            .as_deref()
            .ok_or(ErrorCode::ParamsUserAvatarLengthInvalid)?;

        if !avatar.starts_with("data:image/jpeg;base64,") && !avatar.starts_with("http") {
            return Err(ErrorCode::ParamsUserAvatarLengthInvalid);
        }

        Ok(avatar.to_string())
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditNicknameRequest {
    pub nickname: Option<String>,
}

impl Validator for EditNicknameRequest {
    type Data = String;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let nickname = self
            .nickname
            .as_deref()
            .ok_or(ErrorCode::ParamsUserNicknameLengthInvalid)?;

        if nickname.chars().count() > 16 {
            return Err(ErrorCode::ParamsUserNicknameLengthInvalid);
        }

        Ok(nickname.to_string())
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditSloganRequest {
    pub slogan: Option<String>,
}

impl Validator for EditSloganRequest {
    type Data = String;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let slogan = self
            .slogan
            .as_deref()
            .ok_or(ErrorCode::ParamsUserSloganLengthInvalid)?;

        let char_count = slogan.chars().count();
        if char_count <= 3 || char_count > 128 {
            return Err(ErrorCode::ParamsUserSloganLengthInvalid);
        }

        Ok(slogan.to_string())
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditPhoneRequest {
    pub phone: Option<String>,
}

// todo: 验证手机号正则.
impl Validator for EditPhoneRequest {
    type Data = String;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let phone = self
            .phone
            .as_deref()
            .ok_or(ErrorCode::ParamsUserPhoneFormatInvalid)?;

        if !(11..=128).contains(&phone.chars().count()) {
            return Err(ErrorCode::ParamsUserPhoneFormatInvalid);
        }

        Ok(phone.to_string())
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditMfaRequest {
    pub mfa: Option<EditMfaBody>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditMfaBody {
    pub security: Option<EditMfaSecurityBody>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditMfaSecurityBody {
    pub privacy_window: Option<bool>,
    pub app_lock: Option<bool>,
}

/// 校验后的参数：`None` 表示调用方没给该叶子，服务层保持服务端原值（按叶子 merge）
#[derive(Debug, Clone)]
pub struct EditMfaRequestParams {
    pub privacy_window: Option<bool>,
    pub app_lock: Option<bool>,
}

impl Validator for EditMfaRequest {
    type Data = EditMfaRequestParams;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let security = self
            .mfa
            .as_ref()
            .and_then(|mfa| mfa.security.as_ref())
            .ok_or(ErrorCode::ParamsJsonInvalid)?;

        if security.privacy_window.is_none() && security.app_lock.is_none() {
            return Err(ErrorCode::ParamsJsonInvalid);
        }

        Ok(Self::Data {
            privacy_window: security.privacy_window,
            app_lock: security.app_lock,
        })
    }
}

#[derive(Debug, Serialize)]
pub struct DetailResponse {
    pub phone: Option<String>,
    pub config: Option<Config>,
}

impl From<User> for DetailResponse {
    fn from(user: User) -> Self {
        Self {
            phone: user.phone,
            config: user.config.map(|v| v.0),
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::all)]

    use super::*;

    /// 测试场景：`mfa.security` 缺失 → 预期参数错误
    #[test]
    fn edit_mfa_requires_security() {
        let request: EditMfaRequest = serde_json::from_str(r#"{"mfa":{}}"#).unwrap();

        assert_eq!(
            request.validate().unwrap_err(),
            ErrorCode::ParamsJsonInvalid
        );
    }

    /// 测试场景：`security` 存在但两个叶子都未给 → 预期参数错误
    #[test]
    fn edit_mfa_requires_at_least_one_leaf() {
        let request: EditMfaRequest = serde_json::from_str(r#"{"mfa":{"security":{}}}"#).unwrap();

        assert_eq!(
            request.validate().unwrap_err(),
            ErrorCode::ParamsJsonInvalid
        );
    }

    /// 测试场景：只给一个叶子 → 预期另一个为 `None`（按叶子 merge 的前提）
    #[test]
    fn edit_mfa_accepts_partial_leaves() {
        let request: EditMfaRequest =
            serde_json::from_str(r#"{"mfa":{"security":{"app_lock":true}}}"#).unwrap();
        let params = request.validate().unwrap();

        assert_eq!(params.privacy_window, None);
        assert_eq!(params.app_lock, Some(true));
    }

    /// 测试场景：两个叶子都给 → 原样透传
    #[test]
    fn edit_mfa_accepts_both_leaves() {
        let request: EditMfaRequest = serde_json::from_str(
            r#"{"mfa":{"security":{"privacy_window":false,"app_lock":true}}}"#,
        )
        .unwrap();
        let params = request.validate().unwrap();

        assert_eq!(params.privacy_window, Some(false));
        assert_eq!(params.app_lock, Some(true));
    }
}
