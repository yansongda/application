use crate::{Pool, insert, query_optional, update};
use application_kernel::result::ErrorCode;
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct ShortUrl {
    pub id: u64,
    pub short: String,
    pub url: String,
    pub visit: u64,
    pub created_at: DateTime<Local>,
    pub updated_at: DateTime<Local>,
}

#[derive(Debug)]
pub struct CreateShortUrl {
    pub url: String,
    pub short: String,
}

pub async fn fetch(short: &str) -> application_kernel::result::Result<ShortUrl> {
    let sql = "select * from tool.short_url where short = ? limit 1";
    let pool_ref = Pool::mysql("tool")?;

    let result: Option<ShortUrl> = query_optional!(pool_ref, sql, short);

    if let Some(short_url) = result {
        return Ok(short_url);
    }

    Err(ErrorCode::ParamsShortlinkNotFound)
}

pub async fn insert(url: CreateShortUrl) -> application_kernel::result::Result<ShortUrl> {
    let sql = "insert into tool.short_url (short, url) values (?, ?)";
    let pool_ref = Pool::mysql("tool")?;

    let result = insert!(pool_ref, sql, &url.short, &url.url);

    Ok(ShortUrl {
        id: result.last_insert_id(),
        short: url.short,
        url: url.url,
        visit: 0,
        created_at: Local::now(),
        updated_at: Local::now(),
    })
}

pub async fn update_count(id: u64) -> application_kernel::result::Result<()> {
    let sql = "update tool.short_url set visit = visit + 1 where id = ?";
    let pool_ref = Pool::mysql("tool")?;

    let _ = update!(pool_ref, sql, id);

    Ok(())
}
