use reqwest::{Client, Method, Request, RequestBuilder, Url};

use crate::http;
use application_kernel::result::ErrorCode;
use application_kernel::result::Result;
use serde::{Deserialize, Deserializer, de};
use serde_json::Value;
use tracing::error;

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct TokenResponse {
    pub token_type: String,
    pub access_token: String,
    pub scope: String,
    pub expires_in: i64,
    pub refresh_token: String,
    pub id_token: String,
}

#[derive(Debug, Clone, Deserialize)]
struct RawTokenResponse {
    pub token_type: String,
    pub access_token: String,
    pub scope: String,
    pub expires_in: i64,
    pub refresh_token: String,
    pub id_token: String,
}

impl<'de> Deserialize<'de> for TokenResponse {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = Value::deserialize(deserializer)?;

        // 检查 error 字段（数字类型）
        if let Some(error) = value.get("error").and_then(|e| e.as_i64())
            && error != 0
        {
            let err: TokenResponseError =
                serde_json::from_value(value).map_err(de::Error::custom)?;
            return Err(de::Error::custom(format!(
                "第三方错误: 华为 API 响应业务结果出错，请联系管理员: {}",
                err.error_description
            )));
        }

        serde_json::from_value::<RawTokenResponse>(value)
            .map(|raw| TokenResponse {
                token_type: raw.token_type,
                access_token: raw.access_token,
                scope: raw.scope,
                expires_in: raw.expires_in,
                refresh_token: raw.refresh_token,
                id_token: raw.id_token,
            })
            .map_err(de::Error::custom)
    }
}

#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
pub struct TokenResponseError {
    pub error: i64,
    pub error_description: String,
}

pub async fn token(code: &str, app_id: &str, client_secret: &str) -> Result<TokenResponse> {
    let form = [
        ("grant_type", "authorization_code"),
        ("client_id", app_id),
        ("client_secret", client_secret),
        ("code", code),
    ];

    let builder = RequestBuilder::from_parts(
        Client::new(),
        Request::new(
            Method::POST,
            Url::parse("https://oauth-login.cloud.huawei.com/oauth2/v3/token").map_err(|e| {
                error!("URL 解析失败: {:?}", e);
                ErrorCode::ThirdHttpRequest
            })?,
        ),
    )
    .form(&form);

    http::request::<TokenResponse>(builder.build().map_err(|e| {
        error!("请求构建失败: {:?}", e);
        ErrorCode::ThirdHttpRequest
    })?)
    .await
    .map(|response| response.inner)
}

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct TokenInfoResponse {
    pub client_id: String,
    pub expire_in: i64,
    pub union_id: String,
    pub project_id: String,
    pub r#type: i64,
}

#[derive(Debug, Clone, Deserialize)]
struct RawTokenInfoResponse {
    pub client_id: String,
    pub expire_in: i64,
    pub union_id: String,
    pub project_id: String,
    #[serde(rename = "type")]
    pub r#type: i64,
}

impl<'de> Deserialize<'de> for TokenInfoResponse {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = Value::deserialize(deserializer)?;

        if let Some(error) = value.get("error").and_then(|e| e.as_str())
            && !error.is_empty()
        {
            let err: TokenInfoResponseError =
                serde_json::from_value(value).map_err(de::Error::custom)?;
            return Err(de::Error::custom(format!(
                "第三方错误: 华为 API 响应业务结果出错，请联系管理员: {}",
                err.error
            )));
        }

        serde_json::from_value::<RawTokenInfoResponse>(value)
            .map(|raw| TokenInfoResponse {
                client_id: raw.client_id,
                expire_in: raw.expire_in,
                union_id: raw.union_id,
                project_id: raw.project_id,
                r#type: raw.r#type,
            })
            .map_err(de::Error::custom)
    }
}

#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
pub struct TokenInfoResponseError {
    pub error: String,
}

pub async fn token_info(access_token: &str) -> Result<TokenInfoResponse> {
    let form = [("access_token", access_token)];

    let builder = RequestBuilder::from_parts(
        Client::new(),
        Request::new(
            Method::POST,
            Url::parse("https://oauth-api.cloud.huawei.com/rest.php?nsp_fmt=JSON&nsp_svc=huawei.oauth2.user.getTokenInfo").map_err(|e| {
                error!("URL 解析失败: {:?}", e);
                ErrorCode::ThirdHttpRequest
            })?,
        ),
    )
        .form(&form);

    http::request::<TokenInfoResponse>(builder.build().map_err(|e| {
        error!("请求构建失败: {:?}", e);
        ErrorCode::ThirdHttpRequest
    })?)
    .await
    .map(|response| response.inner)
}

#[cfg(test)]
mod tests {
    use super::{TokenInfoResponse, TokenResponse};

    #[test]
    fn deserialize_token_response_success() {
        let value = serde_json::json!({
            "token_type": "Bearer",
            "access_token": "access",
            "scope": "scope",
            "expires_in": 123,
            "refresh_token": "refresh",
            "id_token": "id"
        });

        let resp: TokenResponse = serde_json::from_value(value).expect("should deserialize");
        assert_eq!(resp.token_type, "Bearer");
        assert_eq!(resp.access_token, "access");
        assert_eq!(resp.scope, "scope");
        assert_eq!(resp.expires_in, 123);
        assert_eq!(resp.refresh_token, "refresh");
        assert_eq!(resp.id_token, "id");
    }

    #[test]
    fn deserialize_token_response_error() {
        let value = serde_json::json!({
            "error": 10001,
            "error_description": "bad code"
        });

        let err = serde_json::from_value::<TokenResponse>(value).expect_err("should fail");
        assert!(
            err.to_string()
                .contains("第三方错误: 华为 API 响应业务结果出错，请联系管理员: bad code")
        );
    }

    #[test]
    fn deserialize_token_info_response_success() {
        let value = serde_json::json!({
            "client_id": "client",
            "expire_in": 3600,
            "union_id": "uid",
            "project_id": "pid",
            "type": 1
        });

        let resp: TokenInfoResponse = serde_json::from_value(value).expect("should deserialize");
        assert_eq!(resp.client_id, "client");
        assert_eq!(resp.expire_in, 3600);
        assert_eq!(resp.union_id, "uid");
        assert_eq!(resp.project_id, "pid");
        assert_eq!(resp.r#type, 1);
    }

    #[test]
    fn deserialize_token_info_response_error() {
        let value = serde_json::json!({
            "error": "invalid_token",
            "error_description": "token expired"
        });

        let err = serde_json::from_value::<TokenInfoResponse>(value).expect_err("should fail");
        assert!(
            err.to_string()
                .contains("第三方错误: 华为 API 响应业务结果出错，请联系管理员: invalid_token")
        );
    }
}
