use crate::account::access_token;
use crate::account::access_token::AccessToken;
use crate::{Pool, insert, query_optional, update};
use application_kernel::config::G_CONFIG;
use application_kernel::result::{ErrorCode, Result};
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use ulid::Ulid;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct RefreshToken {
    pub id: u64,
    pub access_token_id: u64,
    pub refresh_token: String,
    pub expired_at: DateTime<Local>,
    pub created_at: DateTime<Local>,
    pub updated_at: DateTime<Local>,
}

impl RefreshToken {
    pub fn is_expired(&self) -> bool {
        Local::now() > self.expired_at
    }

    pub async fn access_token(&self) -> Result<AccessToken> {
        access_token::fetch_by_id(self.access_token_id).await
    }
}

pub async fn update_or_insert(access_token_id: u64) -> Result<RefreshToken> {
    match fetch_by_access_token_id(access_token_id).await {
        Ok(refresh_token) => update(refresh_token).await,
        Err(_) => insert(access_token_id).await,
    }
}

pub async fn fetch(refresh_token: &str) -> Result<RefreshToken> {
    let sql = "select * from account.refresh_token where refresh_token = ? limit 1";
    let pool_ref = Pool::mysql("account")?;

    let result: Option<RefreshToken> = query_optional!(pool_ref, sql, refresh_token);

    if let Some(data) = result {
        return Ok(data);
    }

    Err(ErrorCode::ParamsRefreshTokenNotFound)
}

pub async fn fetch_by_access_token_id(access_token_id: u64) -> Result<RefreshToken> {
    let sql = "select * from account.refresh_token where access_token_id = ? limit 1";
    let pool_ref = Pool::mysql("account")?;

    let result: Option<RefreshToken> = query_optional!(pool_ref, sql, access_token_id);

    if let Some(data) = result {
        return Ok(data);
    }

    Err(ErrorCode::ParamsRefreshTokenNotFound)
}

pub async fn insert(access_token_id: u64) -> Result<RefreshToken> {
    let sql = "insert into account.refresh_token (access_token_id, refresh_token, expired_at) values (?, ?, ?)";
    let refresh_token = Ulid::generate().to_string();
    let expired_at = G_CONFIG.access_token.get_refresh_expired_at();
    let pool_ref = Pool::mysql("account")?;

    let result = insert!(pool_ref, sql, access_token_id, &refresh_token, expired_at);

    Ok(RefreshToken {
        id: result.last_insert_id(),
        access_token_id,
        refresh_token,
        expired_at,
        created_at: Local::now(),
        updated_at: Local::now(),
    })
}

pub async fn update(mut refresh_token: RefreshToken) -> Result<RefreshToken> {
    let sql = "update account.refresh_token set refresh_token = ?, expired_at = ? where id = ?";
    let refresh_token_value = Ulid::generate().to_string();
    let expired_at = G_CONFIG.access_token.get_refresh_expired_at();
    let pool_ref = Pool::mysql("account")?;

    let _ = update!(
        pool_ref,
        sql,
        &refresh_token_value,
        expired_at,
        refresh_token.id
    );

    refresh_token.refresh_token = refresh_token_value;
    refresh_token.expired_at = expired_at;
    refresh_token.updated_at = Local::now();

    Ok(refresh_token)
}
