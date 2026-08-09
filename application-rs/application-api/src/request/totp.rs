use crate::request::Validator;
use application_database::tool::totp::{Totp, TotpConfig};
use application_kernel::result::ErrorCode;
use serde::{Deserialize, Serialize};
use std::ops::Deref;

#[derive(Debug, Clone, Deserialize)]
pub struct DetailRequest {
    pub id: Option<String>,
}

impl Validator for DetailRequest {
    type Data = u64;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let id = self.id.as_deref().ok_or(ErrorCode::ParamsTotpIdEmpty)?;

        id.parse::<u64>().map_err(|_| ErrorCode::ParamsTotpIdEmpty)
    }
}

#[derive(Debug, Serialize)]
pub struct DetailResponse {
    pub id: String,
    pub issuer: String,
    pub username: String,
    pub config: DetailResponseConfig,
    pub code: String,
}

#[derive(Debug, Serialize)]
pub struct DetailResponseConfig {
    pub period: u64,
}

impl TryFrom<Totp> for DetailResponse {
    type Error = application_kernel::result::ErrorCode;

    fn try_from(totp: Totp) -> application_kernel::result::Result<Self> {
        Ok(Self {
            id: totp.id.to_string(),
            issuer: totp
                .issuer
                .clone()
                .unwrap_or_else(|| "未知发行方".to_string()),
            username: totp.username.clone(),
            config: totp.config.deref().clone().into(),
            code: totp.generate_code()?,
        })
    }
}

impl From<TotpConfig> for DetailResponseConfig {
    fn from(config: TotpConfig) -> Self {
        Self {
            period: config.period,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateRequest {
    pub uri: Option<String>,
}

impl Validator for CreateRequest {
    type Data = String;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let uri = self
            .uri
            .as_deref()
            .ok_or(ErrorCode::ParamsTotpUriFormatInvalid)?;

        if !uri.starts_with("otpauth://totp/") {
            return Err(ErrorCode::ParamsTotpUriFormatInvalid);
        }

        Ok(uri.to_string())
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditIssuerRequest {
    pub id: Option<String>,
    pub issuer: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditIssuerRequestParams {
    pub id: u64,
    pub issuer: String,
}

impl Validator for EditIssuerRequest {
    type Data = EditIssuerRequestParams;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let id = self
            .id
            .as_deref()
            .ok_or(ErrorCode::ParamsTotpIdEmpty)?
            .parse::<u64>()
            .map_err(|_| ErrorCode::ParamsTotpIdEmpty)?;

        if let Some(issuer) = &self.issuer
            && issuer.chars().count() > 128
        {
            return Err(ErrorCode::ParamsTotpIssuerMaxLengthReached);
        }

        Ok(Self::Data {
            id,
            issuer: self.issuer.clone().unwrap_or_default(),
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditUsernameRequest {
    pub id: Option<String>,
    pub username: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditUsernameRequestParams {
    pub id: u64,
    pub username: String,
}

impl Validator for EditUsernameRequest {
    type Data = EditUsernameRequestParams;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let id = self
            .id
            .as_deref()
            .ok_or(ErrorCode::ParamsTotpIdEmpty)?
            .parse::<u64>()
            .map_err(|_| ErrorCode::ParamsTotpIdEmpty)?;

        let username = self
            .username
            .as_deref()
            .ok_or(ErrorCode::ParamsTotpUsernameFormatInvalid)?;

        if username.is_empty() || username.chars().count() > 128 {
            return Err(ErrorCode::ParamsTotpUsernameFormatInvalid);
        }

        Ok(Self::Data {
            id,
            username: username.to_string(),
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct DeleteRequest {
    pub id: Option<String>,
}

impl Validator for DeleteRequest {
    type Data = u64;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let id = self.id.as_deref().ok_or(ErrorCode::ParamsTotpIdEmpty)?;

        id.parse::<u64>().map_err(|_| ErrorCode::ParamsTotpIdEmpty)
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct SortRequest {
    pub items: Option<Vec<SortRequestItem>>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SortRequestItem {
    pub id: Option<String>,
    pub sort: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct SortItemParams {
    pub id: u64,
    pub sort: u32,
}

impl Validator for SortRequest {
    type Data = Vec<SortItemParams>;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let items = self.items.as_ref().ok_or(ErrorCode::ParamsTotpIdEmpty)?;

        if items.is_empty() {
            return Err(ErrorCode::ParamsTotpIdEmpty);
        }

        items
            .iter()
            .map(|item| {
                let id = item
                    .id
                    .as_deref()
                    .ok_or(ErrorCode::ParamsTotpIdEmpty)?
                    .parse::<u64>()
                    .map_err(|_| ErrorCode::ParamsTotpIdEmpty)?;

                let sort = item.sort.ok_or(ErrorCode::ParamsTotpIdEmpty)?;

                Ok(SortItemParams { id, sort })
            })
            .collect()
    }
}
