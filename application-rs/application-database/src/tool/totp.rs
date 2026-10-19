use crate::{Pool, delete, insert, query_all, query_optional, update};
use application_kernel::result::{ErrorCode, Result};
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use sqlx::types::Json;
use std::time::Instant;
use totp_rs::{Algorithm, Builder, Secret};
use tracing::error;
use tracing::info;
use tracing::warn;

/// 校验码位数的兜底值：存量数据（`config` 中无 `digits`）与非法配置均按此值算码。
const DEFAULT_DIGITS: u8 = 6;

/// 校验码位数是否受支持：RFC 4226 允许 6~8 位，越界会让 totp-rs 在生成时 panic。
pub fn is_supported_digits(digits: u8) -> bool {
    (6..=8).contains(&digits)
}

fn default_digits() -> u8 {
    DEFAULT_DIGITS
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SortItem {
    pub id: u64,
    pub sort: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Totp {
    pub id: u64,
    pub user_id: u64,
    pub sort: u32,
    pub username: String,
    pub issuer: Option<String>,
    pub config: Json<TotpConfig>,
    pub created_at: DateTime<Local>,
    pub updated_at: DateTime<Local>,
}

impl Totp {
    pub fn ensure_permission(&self, user_id: u64) -> Result<()> {
        if self.user_id == user_id {
            return Ok(());
        }

        Err(ErrorCode::AuthorizationPermissionUngranted)
    }

    pub fn generate_code(&self) -> Result<String> {
        let config = &self.config;

        let secret = Secret::try_from_base32(&config.secret).map_err(|e| {
            error!("TOTP Secret 解码失败: {:?}", e);
            ErrorCode::ParamsTotpUriFormatInvalid
        })?;

        let digits = if is_supported_digits(config.digits) {
            config.digits
        } else {
            // 脏数据（手工改动或历史版本写入）不应让接口整体失败，回退默认值继续可用
            warn!(
                "TOTP digits 非法，回退默认值: id = {}, digits = {}",
                self.id, config.digits
            );
            DEFAULT_DIGITS
        };

        // 非 RFC 合规构建：第三方服务的 secret 可能短于 RFC 6238 建议长度，需跳过校验
        let totp = Builder::new()
            .with_algorithm(Algorithm::SHA1)
            .with_digits(digits)
            .with_skew(1)
            .with_step_duration(config.period)
            .with_secret(secret)
            .with_issuer(self.issuer.clone())
            .with_account_name(self.username.clone())
            .build_noncompliant();

        Ok(totp.generate_current().to_string())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TotpConfig {
    pub secret: String,
    pub period: u64,
    /// 校验码位数，缺省（存量数据）为 6；仅 6~8 有效
    #[serde(default = "default_digits")]
    pub digits: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreatedTotp {
    pub user_id: u64,
    pub sort: Option<u32>,
    pub username: String,
    pub issuer: Option<String>,
    pub config: TotpConfig,
}

pub async fn all(user_id: u64) -> Result<Vec<Totp>> {
    let sql = "select * from tool.totp where user_id = ? order by sort desc, id asc";
    let pool_ref = Pool::mysql("tool")?;

    Ok(query_all!(pool_ref, sql, user_id))
}

pub async fn fetch(id: u64) -> Result<Totp> {
    let sql = "select * from tool.totp where id = ? limit 1";
    let pool_ref = Pool::mysql("tool")?;

    let result: Option<Totp> = query_optional!(pool_ref, sql, id);

    if let Some(user) = result {
        return Ok(user);
    }

    Err(ErrorCode::ParamsTotpNotFound)
}

pub async fn insert(totp: CreatedTotp) -> Result<Totp> {
    let sql = "insert into tool.totp (user_id, username, issuer, config) values (?, ?, ?, ?)";
    let pool_ref = Pool::mysql("tool")?;

    let result = insert!(
        pool_ref,
        sql,
        totp.user_id,
        &totp.username,
        &totp.issuer,
        Json(&(totp.config))
    );

    Ok(Totp {
        id: result.last_insert_id(),
        user_id: totp.user_id,
        sort: 0,
        username: totp.username,
        issuer: totp.issuer,
        config: Json(totp.config),
        created_at: Local::now(),
        updated_at: Local::now(),
    })
}

pub async fn update_issuer(id: u64, issuer: &str) -> Result<()> {
    let sql = "update tool.totp set issuer = ? where id = ?";
    let pool_ref = Pool::mysql("tool")?;

    let _ = update!(pool_ref, sql, issuer, id);

    Ok(())
}

pub async fn update_username(id: u64, username: &str) -> Result<()> {
    let sql = "update tool.totp set username = ? where id = ?";
    let pool_ref = Pool::mysql("tool")?;

    let _ = update!(pool_ref, sql, username, id);

    Ok(())
}

pub async fn delete(id: u64) -> Result<()> {
    let sql = "delete from tool.totp where id = ?";
    let pool_ref = Pool::mysql("tool")?;

    let _ = delete!(pool_ref, sql, id);

    Ok(())
}

pub async fn delete_by_user(user_id: u64) -> Result<()> {
    let sql = "delete from tool.totp where user_id = ?";
    let pool_ref = Pool::mysql("tool")?;

    let _ = delete!(pool_ref, sql, user_id);

    Ok(())
}

pub async fn sort(user_id: u64, items: &[SortItem]) -> Result<()> {
    if items.is_empty() {
        return Ok(());
    }

    let started_at = Instant::now();
    let pool_ref = Pool::mysql("tool")?;

    let mut sql = String::from("UPDATE tool.totp SET sort = CASE id ");
    for _ in items {
        sql.push_str("WHEN ? THEN ? ");
    }
    sql.push_str("ELSE sort END WHERE id IN (");
    for i in 0..items.len() {
        if i > 0 {
            sql.push(',');
        }
        sql.push('?');
    }
    sql.push_str(") AND user_id = ?");

    // 动态部分仅为占位符结构（CASE WHEN / IN 的数量），无用户输入进入 SQL 文本。
    let mut query = sqlx::query(sqlx::AssertSqlSafe(sql.clone()));
    for item in items {
        query = query.bind(item.id).bind(item.sort);
    }
    for item in items {
        query = query.bind(item.id);
    }
    query = query.bind(user_id);

    let result = query.execute(pool_ref.pool).await.map_err(|e| {
        error!("批量更新 TOTP 排序失败: {:?}", e);
        ErrorCode::InternalDatabaseUpdate
    })?;

    // 依赖 sqlx 默认在 MySQL 握手开启 CLIENT_FOUND_ROWS：affected_rows 为匹配行数（含值未变的行），
    // 重复提交相同排序不会误判为越权；若驱动默认行为变化需重新评估此校验。
    if result.rows_affected() != items.len() as u64 {
        return Err(ErrorCode::AuthorizationPermissionUngranted);
    }

    let elapsed = started_at.elapsed().as_secs_f64();
    info!(elapsed, sql, user_id, item_count = items.len());

    Ok(())
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::all,
        clippy::pedantic,
        clippy::unwrap_used,
        clippy::expect_used,
        clippy::panic
    )]

    use super::*;

    const SECRET: &str = "JBSWY3DPEHPK3PXP";

    fn build_totp(digits: u8) -> Totp {
        Totp {
            id: 1,
            user_id: 1,
            sort: 0,
            username: "alice".to_string(),
            issuer: Some("GitHub".to_string()),
            config: Json(TotpConfig {
                secret: SECRET.to_string(),
                period: 30,
                digits,
            }),
            created_at: Local::now(),
            updated_at: Local::now(),
        }
    }

    /// 测试场景：存量行 config 无 digits → 验证 serde 默认值 → 预期 6
    #[test]
    fn totp_config_legacy_row_defaults_digits_to_six() {
        let json = format!(r#"{{"secret":"{SECRET}","period":30}}"#);
        let config: TotpConfig = serde_json::from_str(&json).unwrap();

        assert_eq!(config.digits, 6);
    }

    /// 测试场景：config 显式写入 digits=8 → 验证按存储值反序列化 → 预期 8
    #[test]
    fn totp_config_deserializes_explicit_digits() {
        let json = format!(r#"{{"secret":"{SECRET}","period":30,"digits":8}}"#);
        let config: TotpConfig = serde_json::from_str(&json).unwrap();

        assert_eq!(config.digits, 8);
    }

    /// 测试场景：digits 取 6/7/8 → 验证算码长度跟随配置 → 预期分别 6/7/8 位纯数字
    #[test]
    fn generate_code_respects_configured_digits() {
        for digits in [6u8, 7, 8] {
            let code = build_totp(digits).generate_code().unwrap();

            assert_eq!(code.len(), usize::from(digits), "digits = {digits}");
            assert!(
                code.chars().all(|c| c.is_ascii_digit()),
                "digits = {digits}, code = {code}"
            );
        }
    }

    /// 测试场景：digits=10（totp-rs 生成会 panic 的越界值）→ 验证回退 6 → 预期不 panic 且长度 6
    #[test]
    fn generate_code_falls_back_for_invalid_digits() {
        let code = build_totp(10).generate_code().unwrap();

        assert_eq!(code.len(), 6);
    }

    /// 测试场景：digits 边界值 → 验证仅 6~8 受支持
    #[test]
    fn supported_digits_covers_six_to_eight() {
        assert!(!is_supported_digits(5));
        assert!(is_supported_digits(6));
        assert!(is_supported_digits(8));
        assert!(!is_supported_digits(9));
        assert!(!is_supported_digits(10));
    }
}
