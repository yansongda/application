use application_kernel::events::OUTBOUND_HTTP_REQUEST;
use application_kernel::prometheus::{
    OUTBOUND_HTTP_RESULT_CONNECT_ERROR, OUTBOUND_HTTP_RESULT_PARSE_ERROR,
    OUTBOUND_HTTP_RESULT_REQUEST_ERROR, OUTBOUND_HTTP_RESULT_SUCCESS, OUTBOUND_HTTP_RESULT_TIMEOUT,
};
use application_kernel::result::{ErrorCode, Result};
use reqwest::{Client, Request};
use serde::Deserialize;
use std::sync::LazyLock;
use std::time::Duration;
use tracing::{info, warn};

#[derive(Debug)]
pub struct HttpResponse<T> {
    pub status: u16,
    pub duration: Duration,
    pub inner: T,
}

static G_CLIENT: LazyLock<Client> = LazyLock::new(|| {
    #[allow(clippy::expect_used)]
    Client::builder()
        .user_agent("yansongda/application-rs")
        .connect_timeout(Duration::from_secs(1))
        .timeout(Duration::from_secs(3))
        .pool_idle_timeout(Duration::from_secs(30))
        .pool_max_idle_per_host(8)
        .tcp_keepalive(Duration::from_mins(1))
        .tcp_nodelay(true)
        .build()
        .expect("HTTP 客户端初始化失败")
});

pub async fn request<T>(req: Request) -> Result<HttpResponse<T>>
where
    T: for<'de> Deserialize<'de>,
{
    let url = normalize_url(req.url().as_str());

    info!("请求第三方服务接口 {:?}", req);

    let started_at = std::time::Instant::now();

    let response = G_CLIENT
        .execute(req)
        .await
        .map_err(|e| classify_http_error(&e, "请求第三方服务接口失败", &url, started_at))?;

    let duration = started_at.elapsed();

    let status = response.status().as_u16();
    let headers = response
        .headers()
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_str().unwrap_or("").to_string()))
        .collect::<Vec<(String, String)>>();

    let body = response
        .text()
        .await
        .map_err(|e| classify_http_error(&e, "接收第三方服务接口响应失败", &url, started_at))?;

    info!(
        "请求第三方服务接口结果：duration: {:?}, status: {}, headers: {:?}, body: {:?}",
        duration, status, &headers, &body
    );

    let inner = serde_json::from_str::<T>(&body).map_err(|e| {
        record_http_error(
            &e,
            "响应解析失败",
            &url,
            started_at,
            ErrorCode::ThirdHttpResponseParse,
            OUTBOUND_HTTP_RESULT_PARSE_ERROR,
        )
    })?;

    tracing::info!(
        event = OUTBOUND_HTTP_REQUEST,
        url = %url,
        result = OUTBOUND_HTTP_RESULT_SUCCESS,
        duration_seconds = duration.as_secs_f64()
    );

    Ok(HttpResponse {
        status,
        duration,
        inner,
    })
}

fn classify_http_error(
    e: &reqwest::Error,
    context: &str,
    url: &str,
    started_at: std::time::Instant,
) -> ErrorCode {
    let (err, label) = if e.is_timeout() {
        (ErrorCode::ThirdHttpRequest, OUTBOUND_HTTP_RESULT_TIMEOUT)
    } else if e.is_connect() {
        (
            ErrorCode::ThirdHttpRequest,
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

fn record_http_error<E: std::fmt::Debug>(
    e: &E,
    context: &str,
    url: &str,
    started_at: std::time::Instant,
    err: ErrorCode,
    label: &'static str,
) -> ErrorCode {
    warn!("{context} {:?}", e);

    tracing::info!(
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
