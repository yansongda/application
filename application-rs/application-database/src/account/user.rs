use crate::{Pool, insert, query_optional, update};
use application_kernel::result::ErrorCode;
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use sqlx::types::Json;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct User {
    pub id: u64,
    pub phone: Option<String>,
    pub config: Option<Json<Config>>,
    pub created_at: DateTime<Local>,
    pub updated_at: DateTime<Local>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Config {
    pub avatar: Option<String>,
    pub nickname: Option<String>,
    pub slogan: Option<String>,
}

pub async fn fetch(user_id: u64) -> application_kernel::result::Result<User> {
    let sql = "select * from account.user where id = ? limit 1";
    let pool_ref = Pool::mysql("account")?;

    let result: Option<User> = query_optional!(pool_ref, sql, user_id);

    if let Some(user) = result {
        return Ok(user);
    }

    Err(ErrorCode::ParamsUserNotFound)
}

pub async fn insert(
    phone: Option<&str>,
    config: Config,
) -> application_kernel::result::Result<u64> {
    let sql = "insert into account.user (phone, config) values (?, ?)";
    let pool_ref = Pool::mysql("account")?;

    let result = insert!(pool_ref, sql, phone, Json(&config));

    Ok(result.last_insert_id())
}

pub async fn update_avatar(id: u64, avatar: &str) -> application_kernel::result::Result<()> {
    let sql = "update account.user set config = json_set(config, '$.avatar', ?) where id = ?";
    let pool_ref = Pool::mysql("account")?;

    let _ = update!(pool_ref, sql, avatar, id);

    Ok(())
}

pub async fn update_nickname(id: u64, nickname: &str) -> application_kernel::result::Result<()> {
    let sql = "update account.user set config = json_set(config, '$.nickname', ?) where id = ?";
    let pool_ref = Pool::mysql("account")?;

    let _ = update!(pool_ref, sql, nickname, id);

    Ok(())
}

pub async fn update_slogan(id: u64, slogan: &str) -> application_kernel::result::Result<()> {
    let sql = "update account.user set config = json_set(config, '$.slogan', ?) where id = ?";
    let pool_ref = Pool::mysql("account")?;

    let _ = update!(pool_ref, sql, slogan, id);

    Ok(())
}

pub async fn update_phone(id: u64, phone: &str) -> application_kernel::result::Result<()> {
    let sql = "update account.user set phone = ? where id = ?";
    let pool_ref = Pool::mysql("account")?;

    let _ = update!(pool_ref, sql, phone, id);

    Ok(())
}

pub async fn flush(id: u64) -> application_kernel::result::Result<()> {
    let sql = "update account.user set phone = ?, config = ? where id = ?";
    let pool_ref = Pool::mysql("account")?;

    let _ = update!(pool_ref, sql, None::<&str>, Json(&Config::default()), id);

    Ok(())
}
