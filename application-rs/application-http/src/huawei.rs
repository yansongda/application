use crate::http::{self, Body};
use application_kernel::result::{ErrorCode, Result};
use serde::Deserialize;
use serde_json::Value;
use tracing::{error, warn};

const OAUTH_TOKEN_URL: &str = "https://oauth-login.cloud.huawei.com/oauth2/v3/token";
const TOKEN_INFO_URL: &str = "https://oauth-api.cloud.huawei.com/rest.php?nsp_fmt=JSON&nsp_svc=huawei.oauth2.user.getTokenInfo";

#[derive(Debug, Clone, Deserialize)]
pub struct TokenResponse {
    pub token_type: String,
    pub access_token: String,
    pub scope: String,
    pub expires_in: i64,
    pub refresh_token: String,
    pub id_token: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct TokenResponseError {
    pub error: i64,
    pub error_description: Option<String>,
}

impl Body for TokenResponse {
    type Error = TokenResponseError;

    fn is_success(body: &Value) -> bool {
        body.get("error")
            .and_then(Value::as_i64)
            .is_none_or(|error| error == 0)
    }
}

pub async fn token(code: &str, app_id: &str, client_secret: &str) -> Result<TokenResponse> {
    let form = [
        ("grant_type", "authorization_code"),
        ("client_id", app_id),
        ("client_secret", client_secret),
        ("code", code),
    ];

    let req = http::post(OAUTH_TOKEN_URL)
        .form(&form)
        .build()
        .map_err(|e| {
            error!("请求构建失败: {:?}", e);
            ErrorCode::ThirdHttpRequest
        })?;

    let response = http::request::<TokenResponse>(req).await?;

    match response.body {
        Ok(success) => Ok(success),
        Err(error) => {
            warn!(
                error = error.error,
                error_description = ?error.error_description,
                "华为 OAuth token 业务错误"
            );
            Err(ErrorCode::ThirdHttpResponseResult)
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct TokenInfoResponse {
    pub client_id: String,
    /// 华为 getTokenInfo API 返回字段本身即拼写为 `expire_in`，
    /// 与 OAuth token 接口的 `expires_in` 不同，勿"顺手"修正。
    pub expire_in: i64,
    pub union_id: String,
    pub project_id: String,
    #[serde(rename = "type")]
    pub r#type: i64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct TokenInfoResponseError {
    pub error: String,
}

impl Body for TokenInfoResponse {
    type Error = TokenInfoResponseError;

    fn is_success(body: &Value) -> bool {
        body.get("error")
            .and_then(Value::as_str)
            .is_none_or(str::is_empty)
    }
}

pub async fn token_info(access_token: &str) -> Result<TokenInfoResponse> {
    let form = [("access_token", access_token)];

    let req = http::post(TOKEN_INFO_URL)
        .form(&form)
        .build()
        .map_err(|e| {
            error!("请求构建失败: {:?}", e);
            ErrorCode::ThirdHttpRequest
        })?;

    let response = http::request::<TokenInfoResponse>(req).await?;

    match response.body {
        Ok(success) => Ok(success),
        Err(error) => {
            warn!(error = %error.error, "华为 getTokenInfo 业务错误");
            Err(ErrorCode::ThirdHttpResponseResult)
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::all)]

    use super::*;

    /// 测试场景：TokenResponse 判别 error 数字字段 -> 0 或缺失为成功，非 0 为失败
    #[test]
    fn token_response_is_success() {
        // (a) error 为 0
        assert!(TokenResponse::is_success(&serde_json::json!({"error": 0})));
        // (b) 无 error 字段
        assert!(TokenResponse::is_success(
            &serde_json::json!({"access_token": "x"})
        ));
        // (c) error 非 0
        assert!(!TokenResponse::is_success(
            &serde_json::json!({"error": 10001})
        ));
    }

    /// 测试场景：TokenInfoResponse 判别 error 字符串字段 -> 空串或缺失为成功，非空为失败
    #[test]
    fn token_info_response_is_success() {
        // (a) error 为空串
        assert!(TokenInfoResponse::is_success(
            &serde_json::json!({"error": ""})
        ));
        // (b) 无 error 字段
        assert!(TokenInfoResponse::is_success(
            &serde_json::json!({"client_id": "c"})
        ));
        // (c) error 非空串
        assert!(!TokenInfoResponse::is_success(
            &serde_json::json!({"error": "invalid_token"})
        ));
    }

    /// 测试场景：成功响应六字段 -> 反序列化为 TokenResponse
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

    /// 测试场景：错误响应含 error_description -> 反序列化为 TokenResponseError 且字段相等
    #[test]
    fn deserialize_token_response_error_with_description() {
        let value = serde_json::json!({
            "error": 10001,
            "error_description": "bad code"
        });

        let err: TokenResponseError = serde_json::from_value(value).expect("should deserialize");
        assert_eq!(err.error, 10001);
        assert_eq!(err.error_description, Some("bad code".to_string()));
    }

    /// 测试场景：错误响应无 error_description -> 宽松化反序列化成功且为 None
    #[test]
    fn deserialize_token_response_error_without_description() {
        let value = serde_json::json!({
            "error": 10001
        });

        let err: TokenResponseError = serde_json::from_value(value).expect("should deserialize");
        assert_eq!(err.error, 10001);
        assert_eq!(err.error_description, None);
    }

    /// 测试场景：成功响应五字段含 type rename -> 反序列化为 TokenInfoResponse
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

    /// 测试场景：错误响应 -> 反序列化为 TokenInfoResponseError 且字段相等
    #[test]
    fn deserialize_token_info_response_error() {
        let value = serde_json::json!({
            "error": "invalid_token"
        });

        let err: TokenInfoResponseError =
            serde_json::from_value(value).expect("should deserialize");
        assert_eq!(err.error, "invalid_token");
    }
}
