use crate::request::Validator;
use application_database::account::Platform;
use application_kernel::result::ErrorCode;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize)]
pub struct LoginRequest {
    pub platform: Option<Platform>,
    pub third_id: Option<String>,
    pub code: Option<String>,
}

pub struct LoginRequestParams {
    pub platform: Platform,
    pub third_id: String,
    pub code: String,
}

impl Validator for LoginRequest {
    type Data = LoginRequestParams;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let platform = self
            .platform
            .filter(|p| *p != Platform::Unsupported)
            .ok_or(ErrorCode::ParamsLoginPlatformUnsupported)?;

        let third_id = self
            .third_id
            .as_deref()
            .ok_or(ErrorCode::ParamsLoginPlatformThirdIdFormatInvalid)?;

        if let Some(code) = &self.code
            && code.chars().count() > 8
        {
            return Ok(LoginRequestParams {
                platform,
                third_id: third_id.to_owned(),
                code: code.clone(),
            });
        }

        Err(ErrorCode::ParamsLoginCodeFormatInvalid)
    }
}

#[derive(Debug, Serialize)]
pub struct LoginResponse {
    pub access_token: String,
    pub expired_in: u32,
    pub refresh_token: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct LoginRefreshRequest {
    pub platform: Option<Platform>,
    pub third_id: Option<String>,
    pub refresh_token: Option<String>,
}

pub struct LoginRefreshRequestParams {
    pub platform: Platform,
    pub third_id: String,
    pub refresh_token: String,
}

impl Validator for LoginRefreshRequest {
    type Data = LoginRefreshRequestParams;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let platform = self
            .platform
            .filter(|p| *p != Platform::Unsupported)
            .ok_or(ErrorCode::ParamsLoginPlatformUnsupported)?;

        let third_id = self
            .third_id
            .as_deref()
            .ok_or(ErrorCode::ParamsLoginPlatformThirdIdFormatInvalid)?;

        if let Some(refresh_token) = &self.refresh_token
            && refresh_token.chars().count() > 8
        {
            return Ok(LoginRefreshRequestParams {
                platform,
                third_id: third_id.to_owned(),
                refresh_token: refresh_token.clone(),
            });
        }

        Err(ErrorCode::ParamsLoginCodeFormatInvalid)
    }
}

#[derive(Debug, Serialize)]
pub struct LoginRefreshResponse {
    pub access_token: String,
    pub expired_in: u32,
    pub refresh_token: String,
}
