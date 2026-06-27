use crate::request::access_token::{LoginRefreshRequestParams, LoginRequestParams};
use application_database::account::third_user;
use application_database::account::user;
use application_database::account::{Platform, third_config};
use application_database::account::{access_token, refresh_token};
use application_kernel::result::{Error, Result};
use application_util::{huawei, wechat};

pub async fn login(
    request: &LoginRequestParams,
) -> Result<(refresh_token::RefreshToken, access_token::AccessToken)> {
    let platform = request.platform;
    let (user_id, access_token_data) = match platform {
        Platform::Wechat => login_wechat(request).await,
        Platform::Huawei => login_huawei(request).await,
        _ => Err(Error::ParamsLoginPlatformUnsupported(None)),
    }?;

    let access_token = access_token::update_or_insert(
        &platform,
        request.third_id.as_str(),
        user_id,
        access_token_data,
    )
    .await?;

    Ok((
        refresh_token::update_or_insert(access_token.id).await?,
        access_token,
    ))
}

pub async fn login_refresh(
    request: &LoginRefreshRequestParams,
) -> Result<(refresh_token::RefreshToken, access_token::AccessToken)> {
    let refresh_token = refresh_token::fetch(request.refresh_token.as_str())
        .await
        .map_err(|_| Error::AuthorizationRefreshTokenInvalid(None))?;

    if refresh_token.is_expired() {
        return Err(Error::AuthorizationRefreshTokenExpired(None));
    }

    let access_token = refresh_token.access_token().await?;

    if access_token.platform != request.platform || access_token.third_id != request.third_id {
        return Err(Error::AuthorizationPermissionUngranted(None));
    }

    let data = access_token.data.0.clone();

    Ok((
        refresh_token::update_or_insert(access_token.id).await?,
        access_token::update(access_token, data).await?,
    ))
}

async fn login_wechat(
    request: &LoginRequestParams,
) -> Result<(u64, access_token::AccessTokenData)> {
    let config = third_config::fetch(&Platform::Wechat, request.third_id.as_str()).await?;

    let app_secret = config
        .config
        .as_ref()
        .and_then(|c| c.wechat.as_ref())
        .ok_or(Error::InternalDatabaseDataInvalid(None))?
        .app_secret
        .as_ref();

    let wechat_response =
        wechat::login(request.code.as_str(), config.third_id.as_str(), app_secret).await?;

    let third_user_config = third_user::ThirdUserConfig {
        r#type: "openid".to_string(),
    };

    let user_id = get_user_id(
        &Platform::Wechat,
        wechat_response.openid.as_str(),
        Some(&third_user_config),
    )
    .await?;

    third_user::update_config(
        &Platform::Wechat,
        &wechat_response.openid,
        &third_user_config,
    )
    .await?;

    Ok((
        user_id,
        access_token::AccessTokenData::from(wechat_response),
    ))
}

async fn login_huawei(
    request: &LoginRequestParams,
) -> Result<(u64, access_token::AccessTokenData)> {
    let config = third_config::fetch(&Platform::Huawei, request.third_id.as_str()).await?;

    let app_secret = config
        .config
        .as_ref()
        .and_then(|c| c.huawei.as_ref())
        .ok_or(Error::InternalDatabaseDataInvalid(None))?
        .client_secret
        .as_ref();

    let token_response =
        huawei::token(request.code.as_str(), config.third_id.as_str(), app_secret).await?;
    let token_info_response = huawei::token_info(token_response.access_token.as_str()).await?;

    Ok((
        get_user_id(
            &Platform::Huawei,
            token_info_response.union_id.as_str(),
            None,
        )
        .await?,
        access_token::AccessTokenData {
            wechat: None,
            huawei: Some(access_token::HuaweiAccessTokenData {
                token_type: token_response.token_type,
                scope: token_response.scope,
                refresh_token: token_response.refresh_token,
                client_id: token_info_response.client_id,
                union_id: token_info_response.union_id,
                project_id: token_info_response.project_id,
                r#type: token_info_response.r#type,
            }),
        },
    ))
}

async fn get_user_id(
    platform: &Platform,
    third_id: &str,
    config: Option<&third_user::ThirdUserConfig>,
) -> Result<u64> {
    let result = third_user::fetch(platform, third_id).await;

    if let Ok(user) = result {
        return Ok(user.user_id);
    }

    match result.unwrap_err() {
        Error::ParamsThirdUserNotFound(_) => {
            let user_id = user::insert(None, user::Config::default()).await?;

            third_user::insert(platform, third_id, user_id, config).await?;

            Ok(user_id)
        }
        e => Err(e),
    }
}
