use crate::request::totp::{
    DetailResponse, EditIssuerRequestParams, EditUsernameRequestParams, SortItemParams,
};
use application_database::account::access_token;
use application_database::tool::totp;
use application_kernel::result::{ErrorCode, Result};
use std::collections::BTreeSet;
use totp_rs::{Secret, TOTP};
use tracing::error;

pub async fn all(access_token: &access_token::AccessToken) -> Result<Vec<DetailResponse>> {
    let totp = totp::all(access_token.user_id).await?;

    totp.into_iter()
        .map(std::convert::TryInto::try_into)
        .collect()
}

pub async fn sort(
    access_token: &access_token::AccessToken,
    items: Vec<SortItemParams>,
) -> Result<()> {
    let owned = totp::all(access_token.user_id).await?;
    let owned_ids: BTreeSet<u64> = owned.iter().map(|t| t.id).collect();
    let item_ids: BTreeSet<u64> = items.iter().map(|i| i.id).collect();

    if owned_ids.len() != items.len() || item_ids.len() != items.len() || owned_ids != item_ids {
        return Err(ErrorCode::AuthorizationPermissionUngranted);
    }

    let db_items = items
        .iter()
        .map(|item| totp::SortItem {
            id: item.id,
            sort: item.sort,
        })
        .collect::<Vec<_>>();

    totp::sort(access_token.user_id, &db_items).await
}

pub async fn detail(access_token: &access_token::AccessToken, id: u64) -> Result<DetailResponse> {
    let totp = totp::fetch(id).await?;

    totp.ensure_permission(access_token.user_id)?;

    totp.try_into()
}

pub async fn create(
    access_token: &access_token::AccessToken,
    uri: String,
) -> Result<DetailResponse> {
    let totp = TOTP::from_url_unchecked(uri.as_str()).map_err(|e| {
        error!("TOTP 链接解析失败: {}", e);

        ErrorCode::ParamsTotpParseFailed
    })?;

    totp::insert(totp::CreatedTotp {
        user_id: access_token.user_id,
        sort: None,
        username: totp.account_name,
        issuer: totp.issuer,
        config: totp::TotpConfig {
            period: totp.step,
            secret: Secret::Raw(totp.secret).to_encoded().to_string(),
        },
    })
    .await?
    .try_into()
}

pub async fn edit_issuer(
    access_token: &access_token::AccessToken,
    params: EditIssuerRequestParams,
) -> Result<()> {
    let totp = totp::fetch(params.id).await?;

    totp.ensure_permission(access_token.user_id)?;

    totp::update_issuer(totp.id, params.issuer.as_str()).await?;

    Ok(())
}

pub async fn edit_username(
    access_token: &access_token::AccessToken,
    params: EditUsernameRequestParams,
) -> Result<()> {
    let totp = totp::fetch(params.id).await?;

    totp.ensure_permission(access_token.user_id)?;

    totp::update_username(totp.id, params.username.as_str()).await?;

    Ok(())
}

pub async fn delete(access_token: &access_token::AccessToken, id: u64) -> Result<()> {
    let totp = totp::fetch(id).await?;

    totp.ensure_permission(access_token.user_id)?;

    totp::delete(id).await?;

    Ok(())
}
