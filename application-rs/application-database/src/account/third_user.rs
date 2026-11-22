use crate::account::Platform;
use crate::{Pool, insert, query_optional};
use application_kernel::result::ErrorCode;
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
    pub id: i64,
    pub user_id: i64,
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
    let sql = "select * from third_user where platform = ? and third_id = ? limit 1";
    let pool_ref = Pool::sqlite("account")?;

    let result: Option<ThirdUser> = query_optional!(pool_ref, sql, platform, third_id);

    if let Some(third_user) = result {
        return Ok(third_user);
    }

    Err(ErrorCode::ParamsThirdUserNotFound)
}

pub async fn insert(
    platform: &Platform,
    third_id: &str,
    user_id: i64,
    config: Option<&ThirdUserConfig>,
) -> application_kernel::result::Result<i64> {
    let sql = "insert into third_user (platform, third_id, user_id, config, created_at, updated_at) values (?, ?, ?, ?, ?, ?)";
    let now = Local::now();
    let pool_ref = Pool::sqlite("account")?;

    let result = insert!(
        pool_ref,
        sql,
        platform,
        third_id,
        user_id,
        config.map(Json),
        now,
        now
    );

    Ok(result.last_insert_rowid())
}
