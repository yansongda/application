use application_kernel::config::G_CONFIG;
use application_kernel::events::OUTBOUND_HTTP_REQUEST;
use application_kernel::prometheus::{
    OUTBOUND_HTTP_RESULT_BUSINESS_ERROR, OUTBOUND_HTTP_RESULT_CONNECT_ERROR,
    OUTBOUND_HTTP_RESULT_PARSE_ERROR, OUTBOUND_HTTP_RESULT_REQUEST_ERROR,
    OUTBOUND_HTTP_RESULT_RESPONSE_ERROR, OUTBOUND_HTTP_RESULT_SUCCESS,
    OUTBOUND_HTTP_RESULT_TIMEOUT,
};
use application_kernel::result::{ErrorCode, Result};
use reqwest::{Client, Request, RequestBuilder};
use serde::de::DeserializeOwned;
use serde_json::Value;
use std::sync::LazyLock;
use std::time::{Duration, Instant};
use tracing::{info, warn};

/// 第三方响应体：成功载荷自声明的封套判别规则。
///
/// `is_success` 仅在 HTTP 状态码为 2xx 时被咨询；判别依据是响应体 JSON 的字段约定，
/// 各上游（微信 errcode / 华为 error）约定不同，故由响应类型自行实现。
pub trait Body: std::fmt::Debug + DeserializeOwned {
    /// 业务失败时响应体的类型。
    type Error: std::fmt::Debug + DeserializeOwned;

    /// 判别响应体是否为业务成功。
    fn is_success(body: &Value) -> bool;
}

/// 第三方 HTTP 响应，携带状态码、耗时与判别后的业务结果。
///
/// 外层 `request` 返回 kernel `Result`，传输层错误已归一化为 9800~9805；
/// `body` 为判别后的业务结果，成功载荷即响应类型本身，失败载荷为 `Body::Error`。
#[derive(Debug)]
pub struct Response<T: Body> {
    pub status: u16,
    pub duration: Duration,
    pub body: std::result::Result<T, T::Error>,
}

const USER_AGENT: &str = "yansongda/application-rs";

static G_CLIENT: LazyLock<Client> = LazyLock::new(|| {
    #[allow(clippy::expect_used)]
    Client::builder()
        .user_agent(USER_AGENT)
        .connect_timeout(Duration::from_secs(G_CONFIG.http.connect_timeout_secs))
        .timeout(Duration::from_secs(G_CONFIG.http.timeout_secs))
        .pool_idle_timeout(Duration::from_secs(G_CONFIG.http.pool_idle_timeout_secs))
        .pool_max_idle_per_host(G_CONFIG.http.pool_max_idle_per_host)
        .tcp_keepalive(Duration::from_secs(G_CONFIG.http.tcp_keepalive_secs))
        .tcp_nodelay(true)
        .build()
        .expect("HTTP 客户端初始化失败")
});

pub fn get(url: &str) -> RequestBuilder {
    G_CLIENT.get(url)
}

pub fn post(url: &str) -> RequestBuilder {
    G_CLIENT.post(url)
}

pub async fn request<T: Body>(req: Request) -> Result<Response<T>> {
    let url = normalize_url(req.url().as_str());

    info!("请求第三方服务接口 {:?}", req);

    let started_at = Instant::now();

    let response = G_CLIENT
        .execute(req)
        .await
        .map_err(|e| classify_execute_error(&e, "请求第三方服务接口失败", &url, started_at))?;

    let duration = started_at.elapsed();

    let status = response.status();
    let headers = response
        .headers()
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_str().unwrap_or("").to_string()))
        .collect::<Vec<(String, String)>>();

    let raw_body = response
        .text()
        .await
        .map_err(|e| classify_body_error(&e, "接收第三方服务接口响应失败", &url, started_at))?;

    info!(
        "请求第三方服务接口结果：duration: {:?}, status: {}, headers: {:?}, body: {:?}",
        duration,
        status.as_u16(),
        &headers,
        &raw_body
    );

    let value =
        serde_json::from_str::<Value>(&raw_body).map_err(|e| parse_error(&e, &url, started_at))?;

    let body = if status.is_success() && T::is_success(&value) {
        Ok(serde_json::from_value::<T>(value).map_err(|e| parse_error(&e, &url, started_at))?)
    } else {
        Err(serde_json::from_value::<T::Error>(value)
            .map_err(|e| parse_error(&e, &url, started_at))?)
    };

    let result = if body.is_ok() {
        OUTBOUND_HTTP_RESULT_SUCCESS
    } else {
        OUTBOUND_HTTP_RESULT_BUSINESS_ERROR
    };

    info!(
        event = OUTBOUND_HTTP_REQUEST,
        url = %url,
        result = result,
        duration_seconds = duration.as_secs_f64()
    );

    Ok(Response {
        status: status.as_u16(),
        duration,
        body,
    })
}

/// 执行阶段错误分类：超时->9804，连接失败->9805，其他->9800。
fn classify_execute_error(
    e: &reqwest::Error,
    context: &str,
    url: &str,
    started_at: Instant,
) -> ErrorCode {
    let (err, label) = if e.is_timeout() {
        (ErrorCode::ThirdHttpTimeout, OUTBOUND_HTTP_RESULT_TIMEOUT)
    } else if e.is_connect() {
        (
            ErrorCode::ThirdHttpConnect,
            OUTBOUND_HTTP_RESULT_CONNECT_ERROR,
        )
    } else {
        (
            ErrorCode::ThirdHttpRequest,
            OUTBOUND_HTTP_RESULT_REQUEST_ERROR,
        )
    };

    record_http_error(e, context, url, started_at, err, label)
}

/// 响应体接收阶段错误分类：超时->9804，其他->9801。
fn classify_body_error(
    e: &reqwest::Error,
    context: &str,
    url: &str,
    started_at: Instant,
) -> ErrorCode {
    let (err, label) = if e.is_timeout() {
        (ErrorCode::ThirdHttpTimeout, OUTBOUND_HTTP_RESULT_TIMEOUT)
    } else {
        (
            ErrorCode::ThirdHttpResponse,
            OUTBOUND_HTTP_RESULT_RESPONSE_ERROR,
        )
    };

    record_http_error(e, context, url, started_at, err, label)
}

/// JSON / S / E 反序列化失败统一归类 9802。
fn parse_error(e: &serde_json::Error, url: &str, started_at: Instant) -> ErrorCode {
    record_http_error(
        e,
        "响应解析失败",
        url,
        started_at,
        ErrorCode::ThirdHttpResponseParse,
        OUTBOUND_HTTP_RESULT_PARSE_ERROR,
    )
}

fn record_http_error<E: std::fmt::Debug>(
    e: &E,
    context: &str,
    url: &str,
    started_at: Instant,
    err: ErrorCode,
    label: &'static str,
) -> ErrorCode {
    warn!("{context} {:?}", e);

    info!(
        event = OUTBOUND_HTTP_REQUEST,
        url = url,
        result = label,
        duration_seconds = started_at.elapsed().as_secs_f64()
    );

    err
}

fn normalize_url(url: &str) -> String {
    let end = url.find(['?', '#']).unwrap_or(url.len());

    url[..end].to_string()
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::all,
        clippy::pedantic,
        clippy::unwrap_used,
        clippy::expect_used,
        clippy::panic,
        dead_code
    )]
    use super::*;

    /// 测试场景：normalize_url 去除 query 和 fragment -> 验证各种 URL 格式 -> 预期返回纯 path 部分
    #[test]
    fn normalize_url_strips_query_and_fragment() {
        // (a) 含 query
        assert_eq!(
            normalize_url("https://a.com/api/x?token=1"),
            "https://a.com/api/x"
        );
        // (b) 无 query/fragment
        assert_eq!(normalize_url("https://a.com/api/x"), "https://a.com/api/x");
        // (c) 含 fragment
        assert_eq!(normalize_url("https://a.com/p#sec"), "https://a.com/p");
        // (d) 同时含 query 和 fragment
        assert_eq!(normalize_url("https://a.com/p?a=1#sec"), "https://a.com/p");
        // (e) 空 url
        assert_eq!(normalize_url(""), "");
    }
}
