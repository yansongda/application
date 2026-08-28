use crate::http::{self, ResponseEnvelope, ResponseVariant};
use application_kernel::result::{ErrorCode, Result};
use reqwest::Url;
use serde::Deserialize;
use serde_json::Value;
use tracing::{error, warn};

#[derive(Debug, Clone, Deserialize)]
pub struct LoginResponse {
    pub session_key: String,
    pub unionid: Option<String>,
    pub openid: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct LoginResponseError {
    pub errmsg: String,
    pub errcode: i32,
}

impl ResponseEnvelope for LoginResponse {
    type Error = LoginResponseError;

    fn is_success(body: &Value) -> bool {
        body.get("errcode")
            .and_then(Value::as_i64)
            .is_none_or(|code| code == 0)
    }
}

pub async fn login(code: &str, app_id: &str, app_secret: &str) -> Result<LoginResponse> {
    let query = [
        ("appid", app_id),
        ("secret", app_secret),
        ("js_code", code),
        ("grant_type", "authorization_code"),
    ];

    let url = Url::parse_with_params("https://api.weixin.qq.com/sns/jscode2session", query)
        .map_err(|e| {
            error!("URL 解析失败: {:?}", e);
            ErrorCode::ThirdHttpRequest
        })?;

    let req = http::get(url.as_str()).build().map_err(|e| {
        error!("请求构建失败: {:?}", e);
        ErrorCode::ThirdHttpRequest
    })?;

    let response = http::request::<LoginResponse>(req).await?;

    match response.inner {
        ResponseVariant::Success(success) => Ok(success),
        ResponseVariant::Error(error) => {
            warn!(
                errcode = error.errcode,
                errmsg = %error.errmsg,
                "微信 jscode2session 业务错误"
            );
            Err(ErrorCode::ThirdHttpResponseResult)
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::all)]

    use super::*;

    /// 测试场景：errcode 为 0 -> 判别为业务成功
    #[test]
    fn is_success_true_when_errcode_zero() {
        let v = serde_json::json!({"errcode": 0});

        assert!(LoginResponse::is_success(&v));
    }

    /// 测试场景：无 errcode 字段 -> 判别为业务成功
    #[test]
    fn is_success_true_when_errcode_absent() {
        let v = serde_json::json!({"openid": "oid"});

        assert!(LoginResponse::is_success(&v));
    }

    /// 测试场景：errcode 非 0 -> 判别为业务失败
    #[test]
    fn is_success_false_when_errcode_nonzero() {
        let v = serde_json::json!({"errcode": 40029});

        assert!(!LoginResponse::is_success(&v));
    }

    /// 测试场景：成功响应含 errcode + 三字段 -> 反序列化为 LoginResponse
    #[test]
    fn deserialize_success_response() {
        let value = serde_json::json!({
            "errcode": 0,
            "session_key": "sk",
            "unionid": "uid",
            "openid": "oid"
        });

        let resp: LoginResponse = serde_json::from_value(value).expect("should deserialize");

        assert_eq!(resp.session_key, "sk");
        assert_eq!(resp.unionid, Some("uid".to_string()));
        assert_eq!(resp.openid, "oid");
    }

    /// 测试场景：成功响应无 unionid -> 反序列化为 LoginResponse 且 unionid 为 None
    #[test]
    fn deserialize_success_response_without_unionid() {
        let value = serde_json::json!({
            "errcode": 0,
            "session_key": "sk",
            "openid": "oid"
        });

        let resp: LoginResponse = serde_json::from_value(value).expect("should deserialize");

        assert_eq!(resp.unionid, None);
        assert_eq!(resp.openid, "oid");
    }

    /// 测试场景：错误响应 -> 反序列化为 LoginResponseError 且字段相等
    #[test]
    fn deserialize_error_response() {
        let value = serde_json::json!({
            "errcode": 40029,
            "errmsg": "invalid code"
        });

        let err: LoginResponseError = serde_json::from_value(value).expect("should deserialize");

        assert_eq!(err.errcode, 40029);
        assert_eq!(err.errmsg, "invalid code");
    }
}
