use serde::{Deserialize, Serialize};
use url::Url;

use crate::request::Validator;
use application_database::tool::short_url::ShortUrl;
use application_kernel::config::G_CONFIG;
use application_kernel::result::ErrorCode;

#[derive(Debug, Clone, Deserialize)]
pub struct CreateRequest {
    pub url: Option<String>,
}

impl Validator for CreateRequest {
    type Data = String;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let url = self.url.as_ref().ok_or(ErrorCode::ParamsShortlinkEmpty)?;

        Url::parse(url).map_err(|_| ErrorCode::ParamsShortlinkFormatInvalid)?;

        Ok(url.to_owned())
    }
}

#[derive(Debug, Serialize)]
pub struct CreateResponse {
    pub url: String,
    pub short: String,
}

impl From<ShortUrl> for CreateResponse {
    fn from(model: ShortUrl) -> Self {
        Self {
            url: model.url,
            short: format!("{}/{}", G_CONFIG.short_url.domain.as_str(), model.short),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct DetailRequest {
    pub short: Option<String>,
}

impl Validator for DetailRequest {
    type Data = String;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let short = self.short.as_ref().ok_or(ErrorCode::ParamsShortlinkEmpty)?;

        Ok(short.to_owned())
    }
}

#[derive(Debug, Serialize)]
pub struct DetailResponse {
    pub url: String,
    pub short: String,
}

impl From<ShortUrl> for DetailResponse {
    fn from(model: ShortUrl) -> Self {
        Self {
            url: model.url,
            short: format!("{}/{}", G_CONFIG.short_url.domain.as_str(), model.short),
        }
    }
}
