use crate::id::{bind, from_rowid};
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
    /// MFA 相关配置：按服务分组（`mfa.security` 之外后续可扩 `mfa.totp` 等），
    /// 缺省即老数据（无 `mfa` 键），不写回 null（避免无谓的磁盘变更）
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mfa: Option<ConfigMfa>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ConfigMfa {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub security: Option<MfaConfigSecurity>,
}

/// 元服务本地安全设置的云端副本（字段名与端上 preferences 一一对应，端侧无需再加一层映射）。
/// 只保存「用户意愿值」，绝不涉及 `locked` 等运行态。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct MfaConfigSecurity {
    /// 防截屏（窗口隐私模式）开关
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub privacy_window: Option<bool>,
    /// 应用锁开关
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub app_lock: Option<bool>,
}

pub async fn fetch(user_id: u64) -> application_kernel::result::Result<User> {
    let sql = "select * from user where id = ? limit 1";
    let pool_ref = Pool::get("account")?;

    let result: Option<User> = query_optional!(pool_ref, sql, bind(user_id)?);

    if let Some(user) = result {
        return Ok(user);
    }

    Err(ErrorCode::ParamsUserNotFound)
}

pub async fn insert(
    phone: Option<&str>,
    config: Config,
) -> application_kernel::result::Result<u64> {
    let sql = "insert into user (phone, config, created_at, updated_at) values (?, ?, ?, ?)";
    let now = Local::now();
    let pool_ref = Pool::get("account")?;

    let result = insert!(pool_ref, sql, phone, Json(&config), now, now);

    from_rowid(result.last_insert_rowid())
}

pub async fn update_avatar(id: u64, avatar: &str) -> application_kernel::result::Result<()> {
    let sql =
        "update user set config = json_set(config, '$.avatar', ?), updated_at = ? where id = ?";
    let pool_ref = Pool::get("account")?;

    let _ = update!(pool_ref, sql, avatar, Local::now(), bind(id)?);

    Ok(())
}

pub async fn update_nickname(id: u64, nickname: &str) -> application_kernel::result::Result<()> {
    let sql =
        "update user set config = json_set(config, '$.nickname', ?), updated_at = ? where id = ?";
    let pool_ref = Pool::get("account")?;

    let _ = update!(pool_ref, sql, nickname, Local::now(), bind(id)?);

    Ok(())
}

pub async fn update_slogan(id: u64, slogan: &str) -> application_kernel::result::Result<()> {
    let sql =
        "update user set config = json_set(config, '$.slogan', ?), updated_at = ? where id = ?";
    let pool_ref = Pool::get("account")?;

    let _ = update!(pool_ref, sql, slogan, Local::now(), bind(id)?);

    Ok(())
}

pub async fn update_phone(id: u64, phone: &str) -> application_kernel::result::Result<()> {
    let sql = "update user set phone = ?, updated_at = ? where id = ?";
    let pool_ref = Pool::get("account")?;

    let _ = update!(pool_ref, sql, phone, Local::now(), bind(id)?);

    Ok(())
}

pub async fn update_config(id: u64, config: &Config) -> application_kernel::result::Result<()> {
    let sql = "update user set config = ?, updated_at = ? where id = ?";
    let pool_ref = Pool::get("account")?;
    let config = Json(config);

    let _ = update!(pool_ref, sql, &config, Local::now(), bind(id)?);

    Ok(())
}

pub async fn flush(id: u64) -> application_kernel::result::Result<()> {
    let sql = "update user set phone = ?, config = ?, updated_at = ? where id = ?";
    let pool_ref = Pool::get("account")?;

    let _ = update!(
        pool_ref,
        sql,
        None::<&str>,
        Json(&Config::default()),
        Local::now(),
        bind(id)?
    );

    Ok(())
}
