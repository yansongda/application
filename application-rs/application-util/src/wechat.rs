use reqwest::{Method, Request, Url};
use tracing::error;

use crate::http;
use application_kernel::result::Error;
use application_kernel::result::Result;
use serde::{Deserialize, Deserializer, de};
use serde_json::Value;

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct LoginResponse {
    pub session_key: String,
    pub unionid: Option<String>,
    pub openid: String,
}

#[derive(Debug, Clone, Deserialize)]
struct RawLoginResponse {
    pub session_key: String,
    pub unionid: Option<String>,
    pub openid: String,
}

impl<'de> Deserialize<'de> for LoginResponse {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = Value::deserialize(deserializer)?;

        if let Some(errcode) = value.get("errcode").and_then(|c| c.as_i64()) {
            if errcode == 0 {
                return serde_json::from_value::<RawLoginResponse>(value)
                    .map(|raw| LoginResponse {
                        session_key: raw.session_key,
                        unionid: raw.unionid,
                        openid: raw.openid,
                    })
                    .map_err(de::Error::custom);
            } else {
                let err: LoginResponseError =
                    serde_json::from_value(value).map_err(de::Error::custom)?;
                return Err(de::Error::custom(format!(
                    "第三方错误: 微信 API 响应业务结果出错，请联系管理员: {}",
                    err.errmsg
                )));
            }
        }

        serde_json::from_value::<RawLoginResponse>(value)
            .map(|raw| LoginResponse {
                session_key: raw.session_key,
                unionid: raw.unionid,
                openid: raw.openid,
            })
            .map_err(de::Error::custom)
    }
}

#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
pub struct LoginResponseError {
    pub errmsg: String,
    pub errcode: i32,
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
            Error::ThirdHttpRequest(Some("URL 格式无效".to_string()))
        })?;

    http::request::<LoginResponse>(Request::new(Method::GET, url))
        .await
        .map(|response| response.inner)
}

#[cfg(test)]
mod tests {
    use super::LoginResponse;

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

    #[test]
    fn deserialize_error_response() {
        let value = serde_json::json!({
            "errcode": 40029,
            "errmsg": "invalid code"
        });

        let err = serde_json::from_value::<LoginResponse>(value).expect_err("should fail");

        assert!(
            err.to_string()
                .contains("第三方错误: 微信 API 响应业务结果出错，请联系管理员: invalid code")
        );
    }

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
}
