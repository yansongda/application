use crate::account::Platform;
use crate::{Pool, insert, query_optional, update};
use application_kernel::result::Error;
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use sqlx::types::Json;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThirdUserConfig {
    pub r#type: String, // "openid" | "unionid"
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct ThirdUser {
    pub id: u64,
    pub user_id: u64,
    pub platform: Platform,
    pub third_id: String,
    pub config: Option<Json<ThirdUserConfig>>,
    pub created_at: DateTime<Local>,
    pub updated_at: DateTime<Local>,
}

pub async fn fetch(
    platform: &Platform,
    third_id: &str,
) -> application_kernel::result::Result<ThirdUser> {
    let sql = "select * from account.third_user where platform = ? and third_id = ? limit 1";
    let pool = Pool::mysql("account")?;

    let result: Option<ThirdUser> = query_optional!(pool, sql, platform, third_id);

    if let Some(third_user) = result {
        return Ok(third_user);
    }

    Err(Error::ParamsThirdUserNotFound(None))
}

pub async fn insert(
    platform: &Platform,
    third_id: &str,
    user_id: u64,
    config: Option<&ThirdUserConfig>,
) -> application_kernel::result::Result<u64> {
    let sql =
        "insert into account.third_user (platform, third_id, user_id, config) values (?, ?, ?, ?)";
    let pool = Pool::mysql("account")?;

    let result = insert!(pool, sql, platform, third_id, user_id, config.map(Json));

    Ok(result.last_insert_id())
}

pub async fn update_config(
    platform: &Platform,
    third_id: &str,
    config: &ThirdUserConfig,
) -> application_kernel::result::Result<()> {
    let sql = "update account.third_user set config = ? where platform = ? and third_id = ?";
    let pool = Pool::mysql("account")?;
    let _ = update!(pool, sql, Json(config), platform, third_id);
    Ok(())
}
