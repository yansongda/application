use crate::request::totp::{
    DetailResponse, EditIssuerRequestParams, EditPinnedRequestParams, EditTagsRequestParams,
    EditUsernameRequestParams, SortItemParams, normalize_tags,
};
use crate::service::backup::{self, Envelope, Item};
use application_database::account::access_token;
use application_database::tool::totp;
use application_kernel::result::{ErrorCode, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
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

/// TOTP 备份类型标识：与信封 `kind` 一致。
pub(crate) const BACKUP_KIND_TOTP: &str = "totp";

/// TOTP 备份中的单条数据；字段与 `tool.totp` 的 `config` 语义保持一致。
#[derive(Debug, Clone, Serialize, Deserialize)]
struct TotpBackupItem {
    #[serde(default)]
    issuer: Option<String>,
    #[serde(default = "default_backup_period")]
    period: u64,
    #[serde(default = "default_backup_digits")]
    digits: u8,
    #[serde(default = "default_backup_algorithm")]
    algorithm: String,
    username: String,
    secret: String,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    pinned: bool,
    #[serde(default)]
    sort: u32,
}

fn default_backup_period() -> u64 {
    30
}

fn default_backup_digits() -> u8 {
    6
}

fn default_backup_algorithm() -> String {
    "SHA1".to_string()
}

impl Item for TotpBackupItem {
    const KIND: &'static str = BACKUP_KIND_TOTP;

    fn validate(self) -> Result<Self> {
        let Self {
            issuer,
            username,
            secret,
            period,
            digits,
            algorithm,
            tags,
            pinned,
            sort,
        } = self;

        if username.is_empty() || username.chars().count() > 128 {
            return Err(ErrorCode::ParamsBackupFormatInvalid);
        }

        if let Some(issuer) = &issuer
            && issuer.chars().count() > 128
        {
            return Err(ErrorCode::ParamsBackupFormatInvalid);
        }

        if !(1..=600).contains(&period) || !totp::is_supported_digits(digits) {
            return Err(ErrorCode::ParamsBackupFormatInvalid);
        }

        let algorithm = algorithm
            .parse::<Algorithm>()
            .map_err(|_| ErrorCode::ParamsBackupFormatInvalid)?;

        // 仅接受 RFC4648 大写 base32（导出端固定输出该形态）；解码后再编码可
        // 顺带去掉尾部 padding，保证入库形态统一
        let secret = Secret::try_from_base32(&secret)
            .map_err(|_| ErrorCode::ParamsBackupFormatInvalid)?
            .to_base32();

        if secret.is_empty() || secret.len() > 128 {
            return Err(ErrorCode::ParamsBackupFormatInvalid);
        }

        let tags = normalize_tags(&tags).ok_or(ErrorCode::ParamsBackupFormatInvalid)?;

        Ok(Self {
            issuer: issuer.filter(|issuer| !issuer.is_empty()),
            username,
            secret,
            period,
            digits,
            algorithm: algorithm.as_str().to_string(),
            tags,
            pinned,
            sort,
        })
    }
}

impl TotpBackupItem {
    /// 已通过 [`Item::validate`] 的条目转换为入库对象（不再重复校验）。
    fn into_created(self, user_id: u64) -> totp::CreatedTotp {
        totp::CreatedTotp {
            user_id,
            sort: Some(self.sort),
            username: self.username,
            issuer: self.issuer,
            config: totp::TotpConfig {
                secret: self.secret,
                period: self.period,
                digits: self.digits,
                algorithm: self.algorithm,
                tags: self.tags,
                pinned: self.pinned,
            },
        }
    }
}

impl From<totp::Totp> for TotpBackupItem {
    fn from(row: totp::Totp) -> Self {
        // 与详情接口一致：使用净化后的 digits/algorithm，确保备份中的参数与后端算码一致
        let digits = row.digits();
        let algorithm = row.algorithm().as_str().to_string();
        let config = row.config.0;

        Self {
            issuer: row.issuer,
            period: config.period,
            digits,
            algorithm,
            username: row.username,
            secret: config.secret,
            tags: config.tags,
            pinned: config.pinned,
            sort: row.sort,
        }
    }
}

/// 导出当前用户的全部 TOTP 条目为加密备份信封（由 `service::backup` 按 kind 分发进入）。
pub async fn export_backup(
    access_token: &access_token::AccessToken,
    password: String,
) -> Result<Envelope> {
    let rows = totp::all(access_token.user_id).await?;

    if rows.is_empty() {
        return Err(ErrorCode::ParamsBackupEmpty);
    }

    let items = rows
        .into_iter()
        .map(TotpBackupItem::from)
        .collect::<Vec<_>>();

    backup::seal(&password, &items)
}

/// 导入备份：解密后逐条校验，全部通过后逐条插入（不去重，重复导入即新增）。
pub async fn import_backup(
    access_token: &access_token::AccessToken,
    password: String,
    backup: Value,
) -> Result<u32> {
    let envelope = serde_json::from_value::<Envelope>(backup)
        .map_err(|_| ErrorCode::ParamsBackupFormatInvalid)?;

    let items = backup::open::<TotpBackupItem>(&password, &envelope)?;

    if items.is_empty() {
        return Err(ErrorCode::ParamsBackupFormatInvalid);
    }

    let created = items
        .into_iter()
        .map(|item| item.into_created(access_token.user_id))
        .collect::<Vec<_>>();

    let affected = totp::insert_many(access_token.user_id, &created).await?;

    u32::try_from(affected).map_err(|_| ErrorCode::ParamsBackupLimitExceeded)
}

#[cfg(test)]
mod tests {
    #![allow(clippy::all)]

    use super::*;

    fn sample_item() -> TotpBackupItem {
        TotpBackupItem {
            issuer: None,
            period: 30,
            digits: 6,
            algorithm: "SHA1".to_string(),
            username: "alice".to_string(),
            secret: "JBSWY3DPEHPK3PXP".to_string(),
            tags: Vec::new(),
            pinned: false,
            sort: 0,
        }
    }

    /// 测试场景：标签带空白、issuer 为空串 → 验证归一化 → 预期去空白/None
    #[test]
    fn validate_normalizes_tags_and_issuer() {
        let mut item = sample_item();
        item.issuer = Some(String::new());
        item.tags = vec!["  工作  ".to_string()];

        let validated = item.validate().unwrap();

        assert_eq!(validated.secret, "JBSWY3DPEHPK3PXP");
        assert_eq!(validated.issuer, None);
        assert_eq!(validated.tags, vec!["工作".to_string()]);
    }

    /// 测试场景：非法 base32（含空白、小写）→ 预期格式错误
    #[test]
    fn validate_rejects_invalid_secret() {
        for secret in ["not-base32!", "   ", "jbswy3dpehpk3pxp"] {
            let mut item = sample_item();
            item.secret = secret.to_string();

            assert_eq!(
                item.validate().unwrap_err(),
                ErrorCode::ParamsBackupFormatInvalid,
                "secret = {secret}"
            );
        }
    }

    /// 测试场景：digits 越界 / period 为 0 / username 过长 → 预期格式错误
    #[test]
    fn validate_rejects_out_of_range_fields() {
        let mut item = sample_item();
        item.digits = 5;
        assert!(item.validate().is_err());

        let mut item = sample_item();
        item.period = 0;
        assert!(item.validate().is_err());

        let mut item = sample_item();
        item.username = "a".repeat(129);
        assert!(item.validate().is_err());
    }

    /// 测试场景：超过标签上限 → 预期格式错误
    #[test]
    fn validate_rejects_too_many_tags() {
        let mut item = sample_item();
        item.tags = vec!["a".to_string(), "b".to_string()];

        assert!(item.validate().is_err());
    }

    /// 测试场景：校验通过后转换 → 预期字段与配置完整映射
    #[test]
    fn into_created_maps_fields() {
        let mut item = sample_item();
        item.sort = 7;
        item.pinned = true;
        item.tags = vec!["工作".to_string()];
        let validated = item.validate().unwrap();
        let created = validated.into_created(42);

        assert_eq!(created.user_id, 42);
        assert_eq!(created.sort, Some(7));
        assert_eq!(created.username, "alice");
        assert_eq!(created.config.secret, "JBSWY3DPEHPK3PXP");
        assert_eq!(created.config.algorithm, "SHA1");
        assert_eq!(created.config.tags, vec!["工作".to_string()]);
        assert!(created.config.pinned);
    }
}
