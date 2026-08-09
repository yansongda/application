//! Prometheus 指标收集模块。
//!
//! 所有指标在首次访问时通过 `LazyLock` 注册到默认 registry，由 `/metrics` 端点导出。
//!
//! # Panics
//!
//! 指标注册失败属于启动期不可恢复错误，通过 `LazyLock` 内部的 `.unwrap()` 直接 panic。
//! `LazyLock` 闭包不能返回 `Result`，且指标注册失败意味着 Prometheus registry 不可用，
//! 服务无法正常提供 `/metrics` 端点，应立即终止启动。
#![allow(clippy::unwrap_used)]

use prometheus::{
    HistogramOpts, HistogramVec, IntCounterVec, Opts, register_histogram_vec,
    register_int_counter_vec,
};
use std::sync::LazyLock;

/// 请求耗时直方图 buckets（秒），覆盖 5ms ~ 10s。
///
/// `http_request_duration_seconds` / `outbound_http_request_duration_seconds` 共用此 bucket。
pub const REQUEST_DURATION_BUCKETS: &[f64] = &[0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0, 10.0];

/// SQL 耗时 bucket（秒），覆盖 1ms ~ 5s。
///
/// SQL 通常比 HTTP 快，bucket 下界从 1ms 开始，上界 5s 覆盖慢查询。
pub const SQL_DURATION_BUCKETS: &[f64] = &[0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0];

/// `outbound_http_requests_total` 指标的 `result` label 取值：出站 HTTP 请求成功。
pub const OUTBOUND_HTTP_RESULT_SUCCESS: &str = "success";

/// `outbound_http_requests_total` 指标的 `result` label 取值：出站 HTTP 请求超时。
pub const OUTBOUND_HTTP_RESULT_TIMEOUT: &str = "timeout";

/// `outbound_http_requests_total` 指标的 `result` label 取值：出站 HTTP 请求连接失败。
pub const OUTBOUND_HTTP_RESULT_CONNECT_ERROR: &str = "connect_error";

/// `outbound_http_requests_total` 指标的 `result` label 取值：出站 HTTP 请求发送失败。
pub const OUTBOUND_HTTP_RESULT_REQUEST_ERROR: &str = "request_error";

/// `outbound_http_requests_total` 指标的 `result` label 取值：出站 HTTP 响应解析失败。
pub const OUTBOUND_HTTP_RESULT_PARSE_ERROR: &str = "parse_error";

/// HTTP 请求总数。
///
/// # 标签
/// - `method` — HTTP 方法（GET/POST/PUT/DELETE）
/// - `path` — 路由模板（如 `/health`），**不要**直接用 `req.uri().path()`
///
/// # Cardinality 注意事项
/// - `path` 必须是路由模板，原始 URL 含 path 参数会让 cardinality 爆炸
pub static HTTP_REQUESTS_TOTAL: LazyLock<IntCounterVec> = LazyLock::new(|| {
    register_int_counter_vec!(
        Opts::new("http_requests_total", "HTTP 请求总数"),
        &["method", "path", "status"]
    )
    .unwrap()
});

/// HTTP 请求耗时直方图（秒），按 `method + path` 统计。
///
/// buckets 覆盖 fast-path（5ms）到 slow-path（10s timeout）的完整分布。
/// `status` / `code` 不计入 label，避免 cardinality 爆炸。
pub static HTTP_REQUEST_DURATION_SECONDS: LazyLock<HistogramVec> = LazyLock::new(|| {
    register_histogram_vec!(
        HistogramOpts::new("http_request_duration_seconds", "HTTP 请求耗时（秒）")
            .buckets(REQUEST_DURATION_BUCKETS.to_vec()),
        &["method", "path"]
    )
    .unwrap()
});

/// 出站 HTTP 请求总数（按 `url` / `result` 标签分类）。
///
/// # 标签
/// - `url` — 目标 URL 路径（如 `/api/v1/dispatch`），**不要**用完整 URL
/// - `result` — 请求结果：`success` / `timeout` / `connect_error` / `request_error` / `parse_error`
///
/// # Cardinality 注意事项
/// - `url` 必须是固定路径模板，原始 URL 含查询参数或动态段会让 cardinality 爆炸
pub static OUTBOUND_HTTP_REQUESTS_TOTAL: LazyLock<IntCounterVec> = LazyLock::new(|| {
    register_int_counter_vec!(
        Opts::new("outbound_http_requests_total", "出站 HTTP 请求总数"),
        &["url", "result"]
    )
    .unwrap()
});

/// 出站 HTTP 请求耗时直方图（秒），按 `url` 统计。
///
/// buckets 复用 `REQUEST_DURATION_BUCKETS`，覆盖 5ms ~ 10s。
/// `result` 不计入 label，避免 cardinality 爆炸。
pub static OUTBOUND_HTTP_REQUEST_DURATION_SECONDS: LazyLock<HistogramVec> = LazyLock::new(|| {
    register_histogram_vec!(
        HistogramOpts::new(
            "outbound_http_request_duration_seconds",
            "出站 HTTP 请求耗时（秒）"
        )
        .buckets(REQUEST_DURATION_BUCKETS.to_vec()),
        &["url"]
    )
    .unwrap()
});

/// SQL 执行累计次数。
pub static SQL_EXECUTE_TOTAL: LazyLock<IntCounterVec> = LazyLock::new(|| {
    register_int_counter_vec!(
        Opts::new("sql_execute_total", "SQL 执行累计次数"),
        &["pool"]
    )
    .unwrap()
});

/// SQL 执行耗时（秒）。
pub static SQL_EXECUTE_DURATION_SECONDS: LazyLock<HistogramVec> = LazyLock::new(|| {
    register_histogram_vec!(
        HistogramOpts::new("sql_execute_duration_seconds", "SQL 执行耗时（秒）")
            .buckets(SQL_DURATION_BUCKETS.to_vec()),
        &["pool"]
    )
    .unwrap()
});

/// 收集所有指标并输出 Prometheus 文本格式，供 `/metrics` 端点使用。
///
/// # Panics
///
/// 当 Prometheus encoder 编码失败时 panic -- 实际上不会发生（编码到内存 `Vec<u8>`）。
pub fn gather_metrics() -> String {
    use prometheus::Encoder;
    let encoder = prometheus::TextEncoder::new();
    let metric_families = prometheus::gather();
    let mut buffer = Vec::new();
    encoder.encode(&metric_families, &mut buffer).unwrap();
    String::from_utf8(buffer).unwrap()
}

#[cfg(test)]
#[allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::float_cmp
)]
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
    use std::sync::Mutex;

    /// 序列化所有会读写全局 Prometheus 指标的测试。
    ///
    /// Prometheus 的默认 registry 是进程级全局状态，无法 per-test 隔离；
    /// 多个测试并行 inc/dec 同一个 static 指标会让 delta 断言失败。
    static METRICS_TEST_LOCK: Mutex<()> = Mutex::new(());

    /// 强制初始化全部 6 个 `LazyLock` 指标，确保它们已注册进默认 registry。
    ///
    /// `IntCounterVec` / `HistogramVec` 在没有任何 label 子指标时，
    /// `TextEncoder` 会跳过该 metric family（不输出 `# HELP`），
    /// 所以这里用固定的测试 label 触碰一次，让其产生 0 值样本。
    fn ensure_all_metrics_registered() {
        let _ = HTTP_REQUESTS_TOTAL
            .with_label_values(&["GET", "/__test__", "200"])
            .get();
        let _ = HTTP_REQUEST_DURATION_SECONDS
            .with_label_values(&["GET", "/__test__"])
            .get_sample_count();
        let _ = OUTBOUND_HTTP_REQUESTS_TOTAL
            .with_label_values(&["__test__", "__test__"])
            .get();
        let _ = OUTBOUND_HTTP_REQUEST_DURATION_SECONDS
            .with_label_values(&["__test__"])
            .get_sample_count();
        let _ = SQL_EXECUTE_TOTAL.with_label_values(&["__test__"]).get();
        SQL_EXECUTE_DURATION_SECONDS
            .with_label_values(&["__test__"])
            .observe(0.0);
    }

    /// 注册全部指标后采集一次文本输出，供各断言复用。
    fn gathered_text() -> String {
        ensure_all_metrics_registered();
        gather_metrics()
    }

    /// `gather_metrics()` 应返回合法的 Prometheus 文本格式：首行是 `# HELP`。
    #[test]
    fn gather_metrics_returns_valid_prometheus_text() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        let text = gathered_text();

        assert!(!text.is_empty(), "gather_metrics() 不应返回空字符串");
        assert!(
            text.starts_with("# HELP"),
            "Prometheus 文本格式应以 `# HELP` 开头，实际开头为: {:?}",
            text.lines().next()
        );
        assert!(
            text.contains("# TYPE"),
            "Prometheus 文本格式应包含 `# TYPE` 声明"
        );
    }

    /// 输出应包含 `http_requests_total`（`IntCounterVec`）指标。
    #[test]
    fn gather_metrics_contains_http_requests_total() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        let text = gathered_text();

        assert!(
            text.contains("# TYPE http_requests_total counter"),
            "输出应包含 http_requests_total 且类型为 counter"
        );
    }

    /// 输出应包含 `http_request_duration_seconds`（`HistogramVec`）指标。
    #[test]
    fn gather_metrics_contains_http_request_duration_seconds() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        let text = gathered_text();

        assert!(
            text.contains("# TYPE http_request_duration_seconds histogram"),
            "输出应包含 http_request_duration_seconds 且类型为 histogram"
        );
    }

    /// 输出应包含 `outbound_http_requests_total`（`IntCounterVec`）指标。
    #[test]
    fn gather_metrics_contains_outbound_http_requests_total() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        let text = gathered_text();

        assert!(
            text.contains("# TYPE outbound_http_requests_total counter"),
            "输出应包含 outbound_http_requests_total 且类型为 counter"
        );
    }

    /// 输出应包含 `outbound_http_request_duration_seconds`（`HistogramVec`）指标。
    #[test]
    fn gather_metrics_contains_outbound_http_request_duration_seconds() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        let text = gathered_text();

        assert!(
            text.contains("# TYPE outbound_http_request_duration_seconds histogram"),
            "输出应包含 outbound_http_request_duration_seconds 且类型为 histogram"
        );
    }

    /// 输出应包含 `sql_execute_total`（`IntCounterVec`）指标。
    #[test]
    fn gather_metrics_contains_sql_execute_total() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        let text = gathered_text();

        assert!(
            text.contains("# TYPE sql_execute_total counter"),
            "输出应包含 sql_execute_total 且类型为 counter"
        );
    }

    /// 输出应包含 `sql_execute_duration_seconds`（`HistogramVec`）指标。
    #[test]
    fn gather_metrics_contains_sql_execute_duration_seconds() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        let text = gathered_text();

        assert!(
            text.contains("# TYPE sql_execute_duration_seconds histogram"),
            "输出应包含 sql_execute_duration_seconds 且类型为 histogram"
        );
    }

    /// 全部 6 个指标必须注册并出现在 `/metrics` 输出中。
    #[test]
    fn all_metrics_registered() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        ensure_all_metrics_registered();

        let expected = [
            "http_requests_total",
            "http_request_duration_seconds",
            "outbound_http_requests_total",
            "outbound_http_request_duration_seconds",
            "sql_execute_total",
            "sql_execute_duration_seconds",
        ];

        // 直接从 registry 取 metric family 名称，避免文本前缀匹配带来的歧义
        let names: Vec<String> = prometheus::gather()
            .iter()
            .map(|mf| mf.name().to_owned())
            .collect();

        for name in expected {
            assert!(
                names.iter().any(|n| n == name),
                "指标 {name} 未注册，实际已注册: {names:?}"
            );
        }

        let text = gather_metrics();
        for name in expected {
            assert!(
                text.contains(&format!("# TYPE {name} ")),
                "指标 {name} 未出现在 gather_metrics() 输出中"
            );
        }
    }

    /// `REQUEST_DURATION_BUCKETS` 必须是覆盖 5ms ~ 10s 的 8 个递增 bucket。
    #[test]
    fn request_duration_buckets_defined() {
        assert_eq!(
            REQUEST_DURATION_BUCKETS,
            &[0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0, 10.0],
            "bucket 定义与预期不一致"
        );
        assert_eq!(REQUEST_DURATION_BUCKETS.len(), 8, "应有 8 个 bucket");

        // Prometheus 要求 bucket 上界严格递增，否则 histogram 注册会失败。
        assert!(
            REQUEST_DURATION_BUCKETS.windows(2).all(|w| w[0] < w[1]),
            "bucket 上界必须严格递增"
        );
    }

    /// `SQL_DURATION_BUCKETS` 必须是覆盖 1ms ~ 5s 的 8 个递增 bucket。
    #[test]
    fn sql_duration_buckets_defined() {
        assert_eq!(
            SQL_DURATION_BUCKETS,
            &[0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0],
            "bucket 定义与预期不一致"
        );
        assert_eq!(SQL_DURATION_BUCKETS.len(), 8, "应有 8 个 bucket");

        assert!(
            SQL_DURATION_BUCKETS.windows(2).all(|w| w[0] < w[1]),
            "bucket 上界必须严格递增"
        );
    }
}
