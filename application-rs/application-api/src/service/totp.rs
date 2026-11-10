use crate::backup::{self, BackupEnvelope, BackupItem, MAX_ITEMS};
use crate::request::totp::{
    BackupImportRequestParams, BackupImportResponse, DetailResponse, EditIssuerRequestParams,
    EditPinnedRequestParams, EditTagsRequestParams, EditUsernameRequestParams, SortItemParams,
    normalize_tags,
};
use application_database::account::access_token;
use application_database::tool::totp;
use application_kernel::result::{ErrorCode, Result};
use std::collections::BTreeSet;
use totp_rs::{Algorithm, Secret, Totp};
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
    let totp = Totp::from_url_unchecked(uri.as_str()).map_err(|e| {
        error!("TOTP 链接解析失败: {}", e);

        ErrorCode::ParamsTotpParseFailed
    })?;

    // totp-rs 仅在生成时对 digits/step 做隐式处理：digits 越界会 panic，step 为 0 会除零 panic，
    // 故必须在入库前拦截（from_url_unchecked 不做校验）。
    if !totp::is_supported_digits(totp.digits()) || totp.step() == 0 {
        error!(
            "TOTP 链接参数非法: digits = {}, period = {}",
            totp.digits(),
            totp.step()
        );

        return Err(ErrorCode::ParamsTotpUriFormatInvalid);
    }

    totp::insert(totp::CreatedTotp {
        user_id: access_token.user_id,
        sort: None,
        username: totp.account_name().to_string(),
        issuer: totp.issuer().map(str::to_string),
        config: totp::TotpConfig {
            period: totp.step(),
            secret: totp.secret().to_base32(),
            digits: totp.digits(),
            algorithm: totp.algorithm().as_str().to_string(),
            tags: Vec::new(),
            pinned: false,
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

pub async fn edit_tags(
    access_token: &access_token::AccessToken,
    params: EditTagsRequestParams,
) -> Result<()> {
    let totp = totp::fetch(params.id).await?;

    totp.ensure_permission(access_token.user_id)?;

    let mut config = totp.config.0;
    config.tags = params.tags;

    totp::update_config(totp.id, &config).await
}

pub async fn edit_pinned(
    access_token: &access_token::AccessToken,
    params: EditPinnedRequestParams,
) -> Result<()> {
    let totp = totp::fetch(params.id).await?;

    totp.ensure_permission(access_token.user_id)?;

    let mut config = totp.config.0;
    config.pinned = params.pinned;

    totp::update_config(totp.id, &config).await
}

pub async fn delete(access_token: &access_token::AccessToken, id: u64) -> Result<()> {
    let totp = totp::fetch(id).await?;

    totp.ensure_permission(access_token.user_id)?;

    totp::delete(id).await?;

    Ok(())
}

/// 导出当前用户的全部 TOTP 条目为加密备份信封。
pub async fn backup_export(
    access_token: &access_token::AccessToken,
    password: String,
) -> Result<BackupEnvelope> {
    let rows = totp::all(access_token.user_id).await?;

    if rows.is_empty() {
        return Err(ErrorCode::ParamsTotpBackupEmpty);
    }

    if rows.len() > MAX_ITEMS {
        return Err(ErrorCode::ParamsTotpBackupLimitExceeded);
    }

    let items = rows.into_iter().map(BackupItem::from).collect::<Vec<_>>();

    backup::encrypt(&password, &items)
}

/// 导入备份：解密后逐条校验，全部通过才在单事务内批量插入（不去重，重复导入即新增）。
pub async fn backup_import(
    access_token: &access_token::AccessToken,
    params: BackupImportRequestParams,
) -> Result<BackupImportResponse> {
    let envelope = serde_json::from_value::<BackupEnvelope>(params.backup)
        .map_err(|_| ErrorCode::ParamsTotpBackupFormatInvalid)?;

    let items = backup::decrypt(&params.password, &envelope)?;

    if items.is_empty() {
        return Err(ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    if items.len() > MAX_ITEMS {
        return Err(ErrorCode::ParamsTotpBackupLimitExceeded);
    }

    let created = items
        .into_iter()
        .map(|item| validate_backup_item(access_token.user_id, item))
        .collect::<Result<Vec<_>>>()?;

    let affected = totp::insert_many(access_token.user_id, &created).await?;
    let imported = u32::try_from(affected).map_err(|_| ErrorCode::ParamsTotpBackupLimitExceeded)?;

    Ok(BackupImportResponse { imported })
}

impl From<totp::Totp> for BackupItem {
    fn from(row: totp::Totp) -> Self {
        // 与详情接口一致：使用净化后的 digits/algorithm，确保备份中的参数与后端算码一致
        let digits = row.digits();
        let algorithm = row.algorithm().as_str().to_string();
        let config = row.config.0;

        Self {
            issuer: row.issuer,
            username: row.username,
            secret: config.secret,
            period: config.period,
            digits,
            algorithm,
            tags: config.tags,
            pinned: config.pinned,
            sort: row.sort,
        }
    }
}

/// 校验并归一化单条备份数据，非法字段一律返回备份格式错误。
fn validate_backup_item(user_id: u64, item: BackupItem) -> Result<totp::CreatedTotp> {
    if item.username.is_empty() || item.username.chars().count() > 128 {
        return Err(ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    if let Some(issuer) = &item.issuer
        && issuer.chars().count() > 128
    {
        return Err(ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    if !(1..=600).contains(&item.period) || !totp::is_supported_digits(item.digits) {
        return Err(ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    let algorithm = item
        .algorithm
        .parse::<Algorithm>()
        .map_err(|_| ErrorCode::ParamsTotpBackupFormatInvalid)?;

    if item.secret.is_empty() {
        return Err(ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    // 先解码再编码：拒绝非法 base32，同时把 secret 归一化为大写、无填充
    let secret = Secret::try_from_base32(&item.secret)
        .map_err(|_| ErrorCode::ParamsTotpBackupFormatInvalid)?
        .to_base32();

    if secret.len() > 128 {
        return Err(ErrorCode::ParamsTotpBackupFormatInvalid);
    }

    let tags = normalize_tags(&item.tags).ok_or(ErrorCode::ParamsTotpBackupFormatInvalid)?;

    Ok(totp::CreatedTotp {
        user_id,
        sort: Some(item.sort),
        username: item.username,
        issuer: item.issuer.filter(|issuer| !issuer.is_empty()),
        config: totp::TotpConfig {
            secret,
            period: item.period,
            digits: item.digits,
            algorithm: algorithm.as_str().to_string(),
            tags,
            pinned: item.pinned,
        },
    })
}
