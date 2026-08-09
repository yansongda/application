use crate::account::Platform;
use crate::{Pool, query_optional};

use application_kernel::result::ErrorCode;
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use sqlx::types::Json;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct ThirdConfig {
    pub id: u64,
    pub platform: Platform,
    pub third_id: String,
    pub config: Option<Json<Config>>,
    pub created_at: DateTime<Local>,
    pub updated_at: DateTime<Local>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub wechat: Option<WechatConfig>,
    pub huawei: Option<HuaweiConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WechatConfig {
    pub app_id: String,
    pub app_secret: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HuaweiConfig {
    pub client_id: String,
    pub client_secret: String,
}

pub async fn fetch(
    platform: &Platform,
    third_id: &str,
) -> application_kernel::result::Result<ThirdConfig> {
    let sql = "select * from account.third_config where platform = ? and third_id = ? limit 1";
    let pool_ref = Pool::mysql("account")?;

    let result: Option<ThirdConfig> = query_optional!(pool_ref, sql, platform, third_id);

    if let Some(config) = result {
        return Ok(config);
    }

    Err(ErrorCode::ParamsThirdConfigNotFound)
}
