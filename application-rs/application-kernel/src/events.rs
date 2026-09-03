//! Metrics 事件名常量。
//!
//! 业务代码通过 `tracing::info!(event = EVENT_NAME)` 引用。

/// HTTP 请求记录（同时更新 `CounterVec` 和 `HistogramVec`）。
pub const HTTP_REQUEST: &str = "http_request";

/// SQL 执行记录（同时更新 `CounterVec` 和 `HistogramVec`）。
pub const SQL_EXECUTE: &str = "sql_execute";

/// 出站 HTTP 请求记录（同时更新 `CounterVec` 和 `HistogramVec`，按 url + result 标签分类）。
pub const OUTBOUND_HTTP_REQUEST: &str = "outbound_http_request";

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

    /// 测试场景：所有事件常量均为非空字符串 → 预期每个常量长度 > 0
    #[test]
    fn all_event_constants_are_non_empty() {
        let events = [HTTP_REQUEST, SQL_EXECUTE, OUTBOUND_HTTP_REQUEST];
        for event in events {
            assert!(!event.is_empty(), "事件常量 {event} 应为非空字符串");
        }
    }

    /// 测试场景：所有事件常量互不重复 → 预期集合去重后数量与原始数量一致
    #[test]
    fn all_event_constants_are_unique() {
        let events = [HTTP_REQUEST, SQL_EXECUTE, OUTBOUND_HTTP_REQUEST];
        let mut seen = std::collections::HashSet::new();
        for event in events {
            assert!(seen.insert(event), "事件常量 {event} 重复");
        }
    }
}
