use crate::request::user::EditConfigMfaRequestParams;
use application_database::account::access_token;
use application_database::account::user;
use application_database::tool::totp;
use application_kernel::result::{ErrorCode, Result};

pub async fn detail(id: u64) -> Result<user::User> {
    if id == 0 {
        return Err(ErrorCode::ParamsUserNotFound);
    }

    user::fetch(id).await
}

pub async fn update_avatar(access_token: &access_token::AccessToken, avatar: &str) -> Result<()> {
    user::update_avatar(access_token.user_id, avatar).await
}

pub async fn update_nickname(
    access_token: &access_token::AccessToken,
    nickname: &str,
) -> Result<()> {
    user::update_nickname(access_token.user_id, nickname).await
}

pub async fn update_slogan(access_token: &access_token::AccessToken, slogan: &str) -> Result<()> {
    user::update_slogan(access_token.user_id, slogan).await
}

// todo: 对相同手机号进行账号数据合并
pub async fn update_phone(access_token: &access_token::AccessToken, phone: &str) -> Result<()> {
    user::update_phone(access_token.user_id, phone).await
}

/// 写入 `config.mfa`（目前仅 `security` 子对象）。
/// 按叶子 merge：请求里没给的叶子保持服务端原值，避免「只改防截屏把应用锁重置」。
pub async fn update_config_mfa(
    access_token: &access_token::AccessToken,
    params: EditConfigMfaRequestParams,
) -> Result<()> {
    let mut user = user::fetch(access_token.user_id).await?;
    let mut config = user.config.take().map(|v| v.0).unwrap_or_default();

    let mut mfa = config.mfa.take().unwrap_or_default();
    let mut security = mfa.security.take().unwrap_or_default();

    if let Some(privacy_window) = params.privacy_window {
        security.privacy_window = Some(privacy_window);
    }

    if let Some(app_lock) = params.app_lock {
        security.app_lock = Some(app_lock);
    }

    mfa.security = Some(security);
    config.mfa = Some(mfa);

    user::update_config(user.id, &config).await
}

pub async fn delete(access_token: &access_token::AccessToken) -> Result<()> {
    tokio::try_join!(
        totp::delete_by_user(access_token.user_id),
        user::flush(access_token.user_id)
    )?;

    Ok(())
}
