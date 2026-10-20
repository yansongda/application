use crate::request::Validator;
use application_database::tool::totp::Totp;
use application_kernel::result::ErrorCode;
use serde::{Deserialize, Serialize};

/// 当前标签上限：UI 仍为单标签，数组结构为后续多标签预留。
const MAX_TAGS: usize = 1;
/// 单个标签的最大字符数（按 Unicode 标量计），数据库列为 64 字符。
const MAX_TAG_CHARS: usize = 32;

#[derive(Debug, Clone, Deserialize)]
pub struct DetailRequest {
    pub id: Option<String>,
}

impl Validator for DetailRequest {
    type Data = u64;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let id = self.id.as_deref().ok_or(ErrorCode::ParamsTotpIdEmpty)?;

        id.parse::<u64>().map_err(|_| ErrorCode::ParamsTotpIdEmpty)
    }
}

#[derive(Debug, Serialize)]
pub struct DetailResponse {
    pub id: String,
    pub issuer: String,
    pub username: String,
    pub tags: Vec<String>,
    pub pinned: bool,
    pub config: DetailResponseConfig,
    pub code: String,
}

#[derive(Debug, Serialize)]
pub struct DetailResponseConfig {
    pub secret: String,
    pub period: u64,
    pub digits: u8,
    pub algorithm: String,
}

impl TryFrom<Totp> for DetailResponse {
    type Error = application_kernel::result::ErrorCode;

    fn try_from(totp: Totp) -> application_kernel::result::Result<Self> {
        // digits/algorithm 使用净化后的值，确保下发给前端的参数与后端算码一致
        let config = DetailResponseConfig {
            secret: totp.config.secret.clone(),
            period: totp.config.period,
            digits: totp.digits(),
            algorithm: totp.algorithm().as_str().to_string(),
        };

        Ok(Self {
            id: totp.id.to_string(),
            issuer: totp
                .issuer
                .clone()
                .unwrap_or_else(|| "未知发行方".to_string()),
            username: totp.username.clone(),
            tags: totp.config.tags.clone(),
            pinned: totp.config.pinned,
            config,
            code: totp.generate_code()?,
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateRequest {
    pub uri: Option<String>,
}

impl Validator for CreateRequest {
    type Data = String;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let uri = self
            .uri
            .as_deref()
            .ok_or(ErrorCode::ParamsTotpUriFormatInvalid)?;

        if !uri.starts_with("otpauth://totp/") {
            return Err(ErrorCode::ParamsTotpUriFormatInvalid);
        }

        Ok(uri.to_string())
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditIssuerRequest {
    pub id: Option<String>,
    pub issuer: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditIssuerRequestParams {
    pub id: u64,
    pub issuer: String,
}

impl Validator for EditIssuerRequest {
    type Data = EditIssuerRequestParams;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let id = self
            .id
            .as_deref()
            .ok_or(ErrorCode::ParamsTotpIdEmpty)?
            .parse::<u64>()
            .map_err(|_| ErrorCode::ParamsTotpIdEmpty)?;

        if let Some(issuer) = &self.issuer
            && issuer.chars().count() > 128
        {
            return Err(ErrorCode::ParamsTotpIssuerMaxLengthReached);
        }

        Ok(Self::Data {
            id,
            issuer: self.issuer.clone().unwrap_or_default(),
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditUsernameRequest {
    pub id: Option<String>,
    pub username: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditUsernameRequestParams {
    pub id: u64,
    pub username: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditTagsRequest {
    pub id: Option<String>,
    pub tags: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct EditTagsRequestParams {
    pub id: u64,
    pub tags: Vec<String>,
}

impl Validator for EditTagsRequest {
    type Data = EditTagsRequestParams;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let id = self
            .id
            .as_deref()
            .ok_or(ErrorCode::ParamsTotpIdEmpty)?
            .parse::<u64>()
            .map_err(|_| ErrorCode::ParamsTotpIdEmpty)?;

        if self.tags.len() > MAX_TAGS {
            return Err(ErrorCode::ParamsTotpTagsInvalid);
        }

        let mut tags = Vec::with_capacity(self.tags.len());

        for raw in &self.tags {
            let tag = raw.trim();

            if tag.is_empty() || tag.chars().count() > MAX_TAG_CHARS {
                return Err(ErrorCode::ParamsTotpTagsInvalid);
            }

            if !tags.iter().any(|existing| existing == tag) {
                tags.push(tag.to_string());
            }
        }

        Ok(Self::Data { id, tags })
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct EditPinnedRequest {
    pub id: Option<String>,
    pub pinned: bool,
}

#[derive(Debug, Clone)]
pub struct EditPinnedRequestParams {
    pub id: u64,
    pub pinned: bool,
}

impl Validator for EditPinnedRequest {
    type Data = EditPinnedRequestParams;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let id = self
            .id
            .as_deref()
            .ok_or(ErrorCode::ParamsTotpIdEmpty)?
            .parse::<u64>()
            .map_err(|_| ErrorCode::ParamsTotpIdEmpty)?;

        Ok(Self::Data {
            id,
            pinned: self.pinned,
        })
    }
}

impl Validator for EditUsernameRequest {
    type Data = EditUsernameRequestParams;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let id = self
            .id
            .as_deref()
            .ok_or(ErrorCode::ParamsTotpIdEmpty)?
            .parse::<u64>()
            .map_err(|_| ErrorCode::ParamsTotpIdEmpty)?;

        let username = self
            .username
            .as_deref()
            .ok_or(ErrorCode::ParamsTotpUsernameFormatInvalid)?;

        if username.is_empty() || username.chars().count() > 128 {
            return Err(ErrorCode::ParamsTotpUsernameFormatInvalid);
        }

        Ok(Self::Data {
            id,
            username: username.to_string(),
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct DeleteRequest {
    pub id: Option<String>,
}

impl Validator for DeleteRequest {
    type Data = u64;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let id = self.id.as_deref().ok_or(ErrorCode::ParamsTotpIdEmpty)?;

        id.parse::<u64>().map_err(|_| ErrorCode::ParamsTotpIdEmpty)
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct SortRequest {
    pub items: Option<Vec<SortRequestItem>>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SortRequestItem {
    pub id: Option<String>,
    pub sort: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct SortItemParams {
    pub id: u64,
    pub sort: u32,
}

impl Validator for SortRequest {
    type Data = Vec<SortItemParams>;

    fn validate(&self) -> application_kernel::result::Result<Self::Data> {
        let items = self.items.as_ref().ok_or(ErrorCode::ParamsTotpIdEmpty)?;

        if items.is_empty() {
            return Err(ErrorCode::ParamsTotpIdEmpty);
        }

        items
            .iter()
            .map(|item| {
                let id = item
                    .id
                    .as_deref()
                    .ok_or(ErrorCode::ParamsTotpIdEmpty)?
                    .parse::<u64>()
                    .map_err(|_| ErrorCode::ParamsTotpIdEmpty)?;

                let sort = item.sort.ok_or(ErrorCode::ParamsTotpIdEmpty)?;

                Ok(SortItemParams { id, sort })
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::all)]

    use super::*;

    fn tags_request(id: &str, tags: &[&str]) -> EditTagsRequest {
        EditTagsRequest {
            id: Some(id.to_string()),
            tags: tags.iter().map(|tag| (*tag).to_string()).collect(),
        }
    }

    /// 测试场景：清空标签（空数组）→ 预期校验通过
    #[test]
    fn edit_tags_accepts_empty_array() {
        let params = tags_request("1", &[]).validate().unwrap();

        assert_eq!(params.id, 1);
        assert!(params.tags.is_empty());
    }

    /// 测试场景：单个标签 → 预期校验通过并保留
    #[test]
    fn edit_tags_accepts_single_tag() {
        let params = tags_request("1", &["工作"]).validate().unwrap();

        assert_eq!(params.tags, vec!["工作".to_string()]);
    }

    /// 测试场景：标签前后有空白 → 预期 trim 后入库
    #[test]
    fn edit_tags_trims_whitespace() {
        let params = tags_request("1", &["  工作  "]).validate().unwrap();

        assert_eq!(params.tags, vec!["工作".to_string()]);
    }

    /// 测试场景：超过当前上限（2 个）→ 预期返回标签格式错误
    #[test]
    fn edit_tags_rejects_too_many_tags() {
        let err = tags_request("1", &["工作", "个人"]).validate().unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpTagsInvalid);
    }

    /// 测试场景：标签超过 32 字符 → 预期返回标签格式错误
    #[test]
    fn edit_tags_rejects_too_long_tag() {
        let long = "标".repeat(MAX_TAG_CHARS + 1);
        let err = tags_request("1", &[long.as_str()]).validate().unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpTagsInvalid);
    }

    /// 测试场景：标签为空白字符串 → 预期返回标签格式错误
    #[test]
    fn edit_tags_rejects_blank_tag() {
        let err = tags_request("1", &["   "]).validate().unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpTagsInvalid);
    }

    /// 测试场景：id 非数字 → 预期返回 id 为空错误
    #[test]
    fn edit_tags_rejects_invalid_id() {
        let err = tags_request("abc", &["工作"]).validate().unwrap_err();

        assert_eq!(err, ErrorCode::ParamsTotpIdEmpty);
    }

    /// 测试场景：置顶请求缺少 pinned → 预期 JSON 反序列化失败（缺失必填字段）
    #[test]
    fn edit_pinned_requires_pinned_field() {
        let result = serde_json::from_str::<EditPinnedRequest>(r#"{"id":"1"}"#);

        assert!(result.is_err());
    }

    /// 测试场景：置顶请求完整 → 预期校验通过
    #[test]
    fn edit_pinned_accepts_boolean() {
        let request: EditPinnedRequest =
            serde_json::from_str(r#"{"id":"1","pinned":true}"#).unwrap();
        let params = request.validate().unwrap();

        assert_eq!(params.id, 1);
        assert!(params.pinned);
    }
}
