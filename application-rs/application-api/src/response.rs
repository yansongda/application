use application_kernel::result::ErrorCode;
use salvo::http::ParseError;
use salvo::{Scribe, writing::Json};
use serde::{Deserialize, Serialize};
use tracing::warn;

#[derive(Debug, Serialize, Deserialize)]
pub struct Response<D: Serialize> {
    pub code: i32,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub request_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<D>,
}

impl<D: Serialize> Response<D> {
    pub(crate) fn new(code: Option<i32>, message: Option<String>, data: Option<D>) -> Self {
        Response {
            code: code.unwrap_or(0),
            message: message.unwrap_or_else(|| "success".to_string()),
            request_id: None,
            data,
        }
    }

    pub fn success(data: D) -> Self {
        Self::new(
            Some(ErrorCode::Success.code()),
            Some(ErrorCode::Success.message().to_string()),
            Some(data),
        )
    }

    pub fn error(code: ErrorCode) -> Self {
        Self::new(Some(code.code()), Some(code.message().to_string()), None)
    }
}

fn extract_request_id(res: &salvo::Response) -> Option<String> {
    res.headers()
        .get("x-request-id")
        .and_then(|v| v.to_str().ok())
        .map(std::string::ToString::to_string)
}

impl<D: Serialize + Send> Scribe for Response<D> {
    fn render(mut self, res: &mut salvo::Response) {
        self.request_id = extract_request_id(res);
        res.render(Json(self));
    }
}

pub type Result<D> = std::result::Result<D, AppErr>;
pub type Resp<D> = Result<Response<D>>;

pub struct AppErr(pub ErrorCode);

impl Scribe for AppErr {
    fn render(self, res: &mut salvo::Response) {
        let mut response = Response::<String>::error(self.0);
        response.request_id = extract_request_id(res);
        res.render(Json(response));
    }
}

impl From<ErrorCode> for AppErr {
    fn from(e: ErrorCode) -> Self {
        AppErr(e)
    }
}

impl From<ParseError> for AppErr {
    fn from(err: ParseError) -> Self {
        warn!("解析 Json 请求失败: {:?}", err);
        AppErr(ErrorCode::ParamsJsonInvalid)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_response_success_serialization() {
        let mut response = Response::success("test data");
        response.request_id = Some("test-request-id-123".to_string());
        let json = serde_json::to_value(&response).unwrap();

        assert_eq!(json["code"], 0);
        assert_eq!(json["message"], "success");
        assert_eq!(json["request_id"], "test-request-id-123");
        assert_eq!(json["data"], "test data");
    }

    #[test]
    fn test_response_new_with_request_id() {
        let mut response = Response::<String>::new(Some(404), Some("Not Found".to_string()), None);
        response.request_id = Some("test-request-id-456".to_string());
        let json = serde_json::to_value(&response).unwrap();

        assert_eq!(json["code"], 404);
        assert_eq!(json["message"], "Not Found");
        assert_eq!(json["request_id"], "test-request-id-456");
        assert_eq!(json["data"], serde_json::Value::Null);
    }

    #[test]
    fn test_response_structure() {
        let data = json!({
            "id": 1,
            "name": "test"
        });
        let mut response = Response::success(data.clone());
        response.request_id = Some("req-123".to_string());
        let json = serde_json::to_value(&response).unwrap();

        assert!(json.get("code").is_some());
        assert!(json.get("message").is_some());
        assert!(json.get("request_id").is_some());
        assert!(json.get("data").is_some());

        let keys: Vec<&str> = json
            .as_object()
            .unwrap()
            .keys()
            .map(|s| s.as_str())
            .collect();
        assert_eq!(keys.len(), 4);
        assert!(keys.contains(&"code"));
        assert!(keys.contains(&"message"));
        assert!(keys.contains(&"request_id"));
        assert!(keys.contains(&"data"));
    }

    #[test]
    fn test_json_format_example() {
        let data = json!({"user_id": 1, "username": "test"});
        let mut response = Response::success(data);
        response.request_id = Some("xxxxx".to_string());
        let json_str = serde_json::to_string(&response).unwrap();
        let json_value: serde_json::Value = serde_json::from_str(&json_str).unwrap();

        assert_eq!(json_value["code"], 0);
        assert_eq!(json_value["message"], "success");
        assert_eq!(json_value["request_id"], "xxxxx");
        assert!(json_value["data"].is_object());
        assert_eq!(json_value["data"]["user_id"], 1);
        assert_eq!(json_value["data"]["username"], "test");

        #[cfg(debug_assertions)]
        {
            println!("\nActual JSON output:");
            println!("{}", serde_json::to_string_pretty(&response).unwrap());
        }
    }

    #[test]
    fn test_error_response_access_token_expired_code_1004() {
        let response = Response::<String>::error(ErrorCode::AuthorizationAccessTokenExpired);
        let json = serde_json::to_value(&response).unwrap();

        assert_eq!(json["code"], 1004);
        assert!(json["message"].as_str().unwrap().contains("过期"));
        assert!(json["data"].is_null());
    }

    #[test]
    fn test_error_response_refresh_token_invalid_code_1005() {
        let response = Response::<String>::error(ErrorCode::AuthorizationRefreshTokenInvalid);
        let json = serde_json::to_value(&response).unwrap();

        assert_eq!(json["code"], 1005);
        assert!(json["message"].as_str().unwrap().contains("不正确"));
        assert!(json["data"].is_null());
    }

    #[test]
    fn test_error_response_refresh_token_expired_code_1006() {
        let response = Response::<String>::error(ErrorCode::AuthorizationRefreshTokenExpired);
        let json = serde_json::to_value(&response).unwrap();

        assert_eq!(json["code"], 1006);
        assert!(json["message"].as_str().unwrap().contains("过期"));
        assert!(json["data"].is_null());
    }

    #[test]
    fn test_error_response_auth_codes_are_distinguishable() {
        let cases: Vec<(ErrorCode, i32)> = vec![
            (ErrorCode::AuthorizationAccessTokenExpired, 1004),
            (ErrorCode::AuthorizationRefreshTokenInvalid, 1005),
            (ErrorCode::AuthorizationRefreshTokenExpired, 1006),
        ];

        for (err, expected_code) in cases {
            let response = Response::<String>::error(err);
            let json = serde_json::to_value(&response).unwrap();
            assert_eq!(json["code"], expected_code);
            assert!(json["data"].is_null());
        }
    }

    #[test]
    fn test_error_response_access_token_expired_message() {
        let response = Response::<String>::error(ErrorCode::AuthorizationAccessTokenExpired);
        let json = serde_json::to_value(&response).unwrap();

        assert_eq!(json["code"], 1004);
        assert_eq!(json["message"], "认证失败: 认证信息已过期,请重新登录");
    }

    #[test]
    fn test_app_err_from_error_code() {
        let err: AppErr = ErrorCode::AuthorizationHeaderMissing.into();

        assert_eq!(err.0, ErrorCode::AuthorizationHeaderMissing);
        assert_eq!(err.0.code(), 1000);
        assert_eq!(err.0.message(), "认证失败: 缺少认证信息,请重新登录");
    }

    #[test]
    fn test_app_err_error_code_matches() {
        let cases = [
            ErrorCode::Success,
            ErrorCode::AuthorizationAccessTokenInvalid,
            ErrorCode::ParamsJsonInvalid,
            ErrorCode::ThirdHttpResponse,
            ErrorCode::InternalDatabaseQuery,
        ];

        for code in cases {
            let err = AppErr::from(code);

            assert_eq!(err.0, code);

            let resp = Response::<()>::error(err.0);
            assert_eq!(resp.code, code.code());
            assert_eq!(resp.message, code.message());
        }
    }
}
