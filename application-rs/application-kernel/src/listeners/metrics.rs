//! `MetricsLayer` -- 基于 tracing 事件的声明式 Prometheus 指标收集层。
//!
//! 业务代码用 `tracing::info!(event = HTTP_REQUEST)` 声明"发生了什么"，
//! 本 Layer 自动订阅这些事件并更新对应指标。新增消费者（审计/告警）只需加新 Layer，
//! 业务代码零改动。
//!
//! ## 递归防御
//!
//! unknown 事件分支会发 `tracing::debug!("未知 metrics 事件: {}", name)`，
//! 该 debug 事件不含 `event` 字段。当它重新进入 `on_event` 时，
//! `event_name` 为空会触发提前返回，切断递归链。

use tracing::field::{Field, Visit};
use tracing::{Event, Subscriber};
use tracing_subscriber::Layer;
use tracing_subscriber::layer::{Context, Filter};

use crate::events::{HTTP_REQUEST, OUTBOUND_HTTP_REQUEST, SQL_EXECUTE};
use crate::prometheus::{
    HTTP_REQUEST_DURATION_SECONDS, HTTP_REQUESTS_TOTAL, OUTBOUND_HTTP_REQUEST_DURATION_SECONDS,
    OUTBOUND_HTTP_REQUESTS_TOTAL, SQL_EXECUTE_DURATION_SECONDS, SQL_EXECUTE_TOTAL,
};

/// 收集 tracing 事件字段的访问器。
#[derive(Default)]
struct EventFields {
    event_name: String,
    duration_seconds: Option<f64>,
    method: Option<String>,
    path: Option<String>,
    status: Option<String>,
    result: Option<String>,
    pool: Option<String>,
    url: Option<String>,
}

impl Visit for EventFields {
    fn record_str(&mut self, field: &Field, value: &str) {
        match field.name() {
            "event" => self.event_name = value.to_string(),
            "method" => self.method = Some(value.to_string()),
            "path" => self.path = Some(value.to_string()),
            "status" => self.status = Some(value.to_string()),
            "result" => self.result = Some(value.to_string()),
            "pool" => self.pool = Some(value.to_string()),
            "url" => self.url = Some(value.to_string()),
            _ => {}
        }
    }

    fn record_f64(&mut self, field: &Field, value: f64) {
        match field.name() {
            "duration_seconds" | "latency_seconds" => self.duration_seconds = Some(value),
            _ => {}
        }
    }

    fn record_u64(&mut self, _field: &Field, _value: u64) {}
    fn record_i64(&mut self, _field: &Field, _value: i64) {}
    fn record_debug(&mut self, _field: &Field, _value: &dyn std::fmt::Debug) {}
}

/// 无状态的 tracing Layer，按 `event` 字段名路由事件到 Prometheus 指标。
pub struct MetricsLayer;

impl MetricsLayer {
    pub fn new() -> Self {
        Self
    }
}

impl Default for MetricsLayer {
    fn default() -> Self {
        Self::new()
    }
}

/// 前置过滤：只放行含 `event` 字段的 tracing 事件。
///
/// 与 `HumanReadableFilter` 配合：`fmt::layer` 只输出含 `message` 字段的人类可读日志，
/// 本 filter 确保 `MetricsLayer` 只接收含 `event` 字段的 metrics 事件，
/// 两层过滤各司其职，互不干扰。
pub struct MetricsFilter;

impl<S> Filter<S> for MetricsFilter
where
    S: Subscriber,
{
    fn enabled(&self, meta: &tracing::Metadata<'_>, _: &Context<'_, S>) -> bool {
        meta.fields().field("event").is_some()
    }
}

impl<S> Layer<S> for MetricsLayer
where
    S: Subscriber + for<'a> tracing_subscriber::registry::LookupSpan<'a>,
{
    fn on_event(&self, event: &Event<'_>, _ctx: Context<'_, S>) {
        let mut fields = EventFields::default();
        event.record(&mut fields);

        if fields.event_name.is_empty() {
            return;
        }

        match fields.event_name.as_str() {
            HTTP_REQUEST => {
                HTTP_REQUESTS_TOTAL
                    .with_label_values(&[
                        &fields.method.clone().unwrap_or_default(),
                        &fields.path.clone().unwrap_or_default(),
                        &fields.status.clone().unwrap_or_default(),
                    ])
                    .inc();
                HTTP_REQUEST_DURATION_SECONDS
                    .with_label_values(&[
                        &fields.method.clone().unwrap_or_default(),
                        &fields.path.clone().unwrap_or_default(),
                    ])
                    .observe(fields.duration_seconds.unwrap_or(0.0));
            }

            SQL_EXECUTE => {
                SQL_EXECUTE_TOTAL
                    .with_label_values(&[&fields.pool.clone().unwrap_or_default()])
                    .inc();
                SQL_EXECUTE_DURATION_SECONDS
                    .with_label_values(&[&fields.pool.clone().unwrap_or_default()])
                    .observe(fields.duration_seconds.unwrap_or(0.0));
            }

            OUTBOUND_HTTP_REQUEST => {
                OUTBOUND_HTTP_REQUESTS_TOTAL
                    .with_label_values(&[
                        &fields.url.clone().unwrap_or_default(),
                        &fields.result.clone().unwrap_or_default(),
                    ])
                    .inc();
                OUTBOUND_HTTP_REQUEST_DURATION_SECONDS
                    .with_label_values(&[&fields.url.clone().unwrap_or_default()])
                    .observe(fields.duration_seconds.unwrap_or(0.0));
            }

            unknown => {
                tracing::debug!("未知 metrics 事件: {}", unknown);
            }
        }
    }
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
    use crate::prometheus::{
        self, OUTBOUND_HTTP_RESULT_CONNECT_ERROR, OUTBOUND_HTTP_RESULT_PARSE_ERROR,
        OUTBOUND_HTTP_RESULT_REQUEST_ERROR, OUTBOUND_HTTP_RESULT_TIMEOUT,
    };
    use std::sync::Mutex;

    /// 序列化所有触碰全局 Prometheus counter 的测试，防止并行执行时
    /// 多个测试同时 inc 同一个全局 static counter 导致 delta 断言失败。
    /// Prometheus counter 是进程级全局状态，无法 per-test 隔离。
    static METRICS_TEST_LOCK: Mutex<()> = Mutex::new(());

    /// 构造一个只挂 `MetricsLayer`（无 filter）的 dispatcher，在闭包内执行 metrics 事件。
    ///
    /// 用 `with_default` 确保不影响全局 subscriber（其他测试的 `Logger::init`
    /// 可能已设置全局 subscriber）。与新生产代码一致，MetricsLayer 不再依赖
    /// per-layer filter，而是通过 `event` 字段订阅。
    fn with_metrics_layer<R>(f: impl FnOnce() -> R) -> R {
        use tracing_subscriber::layer::SubscriberExt;

        let subscriber = tracing_subscriber::registry().with(MetricsLayer::new());

        tracing::dispatcher::with_default(&tracing::dispatcher::Dispatch::new(subscriber), f)
    }

    /// 测试场景：发送 `HTTP_REQUEST` 事件 → 验证 `HTTP_REQUESTS_TOTAL` 计数器与 `HTTP_REQUEST_DURATION_SECONDS` 直方图同时更新 → 预期两者均增加
    #[test]
    fn metrics_layer_http_request_updates_counter_and_histogram() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        let before_counter = prometheus::HTTP_REQUESTS_TOTAL
            .with_label_values(&["GET", "/health", "200"])
            .get();
        let before_hist = prometheus::HTTP_REQUEST_DURATION_SECONDS
            .with_label_values(&["GET", "/health"])
            .get_sample_count();
        with_metrics_layer(|| {
            tracing::info!(
                event = HTTP_REQUEST,
                method = "GET",
                path = "/health",
                status = "200",
                duration_seconds = 0.001_f64
            );
        });
        assert!(
            prometheus::HTTP_REQUESTS_TOTAL
                .with_label_values(&["GET", "/health", "200"])
                .get()
                > before_counter,
            "HTTP_REQUESTS_TOTAL should increment"
        );
        assert!(
            prometheus::HTTP_REQUEST_DURATION_SECONDS
                .with_label_values(&["GET", "/health"])
                .get_sample_count()
                > before_hist,
            "HTTP_REQUEST_DURATION_SECONDS sample count should increase"
        );
    }

    /// 测试场景：发送不同 method/path 组合的 `HTTP_REQUEST` 事件 → 验证 `HTTP_REQUESTS_TOTAL` 对应标签计数器 +1 → 预期 delta = 1
    #[test]
    fn metrics_layer_http_request_with_different_path() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        let before = prometheus::HTTP_REQUESTS_TOTAL
            .with_label_values(&["POST", "/messages", "200"])
            .get();
        with_metrics_layer(|| {
            tracing::info!(
                event = HTTP_REQUEST,
                method = "POST",
                path = "/messages",
                status = "200",
                duration_seconds = 0.05_f64
            );
        });
        let after = prometheus::HTTP_REQUESTS_TOTAL
            .with_label_values(&["POST", "/messages", "200"])
            .get();
        assert_eq!(
            after - before,
            1,
            "HTTP_REQUESTS_TOTAL with different path should increment"
        );
    }

    /// 测试场景：发送带 pool / `duration_seconds` 的 `SQL_EXECUTE` 事件 → 验证 `SQL_EXECUTE_TOTAL` 计数器 +1 且 `SQL_EXECUTE_DURATION_SECONDS` 采样数增加
    #[test]
    fn metrics_layer_sql_execute_updates_counter_and_histogram() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        let before_counter = prometheus::SQL_EXECUTE_TOTAL
            .with_label_values(&["default"])
            .get();
        let before_hist = prometheus::SQL_EXECUTE_DURATION_SECONDS
            .with_label_values(&["default"])
            .get_sample_count();
        with_metrics_layer(|| {
            tracing::info!(
                event = SQL_EXECUTE,
                pool = "default",
                duration_seconds = 0.002_f64
            );
        });
        assert!(
            prometheus::SQL_EXECUTE_TOTAL
                .with_label_values(&["default"])
                .get()
                > before_counter,
            "SQL_EXECUTE_TOTAL should increment"
        );
        assert!(
            prometheus::SQL_EXECUTE_DURATION_SECONDS
                .with_label_values(&["default"])
                .get_sample_count()
                > before_hist,
            "SQL_EXECUTE_DURATION_SECONDS sample count should increase"
        );
    }

    /// 测试场景：发送成功路径的 `OUTBOUND_HTTP_REQUEST` 事件 -> 验证 `OUTBOUND_HTTP_REQUESTS_TOTAL` 计数器与 `OUTBOUND_HTTP_REQUEST_DURATION_SECONDS` 直方图同时更新 -> 预期两者均增加
    #[test]
    fn metrics_layer_outbound_http_request_updates_counter_and_histogram() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        let before_counter = prometheus::OUTBOUND_HTTP_REQUESTS_TOTAL
            .with_label_values(&["/api/v1/verify", "success"])
            .get();
        let before_hist = prometheus::OUTBOUND_HTTP_REQUEST_DURATION_SECONDS
            .with_label_values(&["/api/v1/verify"])
            .get_sample_count();
        with_metrics_layer(|| {
            tracing::info!(
                event = OUTBOUND_HTTP_REQUEST,
                url = "/api/v1/verify",
                result = "success",
                duration_seconds = 0.05_f64
            );
        });
        assert!(
            prometheus::OUTBOUND_HTTP_REQUESTS_TOTAL
                .with_label_values(&["/api/v1/verify", "success"])
                .get()
                > before_counter,
            "OUTBOUND_HTTP_REQUESTS_TOTAL should increment"
        );
        assert!(
            prometheus::OUTBOUND_HTTP_REQUEST_DURATION_SECONDS
                .with_label_values(&["/api/v1/verify"])
                .get_sample_count()
                > before_hist,
            "OUTBOUND_HTTP_REQUEST_DURATION_SECONDS sample count should increase"
        );
    }

    /// 测试场景：依次发送 4 种失败结果的 `OUTBOUND_HTTP_REQUEST` 事件 -> 验证每种 result 的 counter +1 且 histogram 采样数增加 -> 预期 4 种失败路径均正确路由
    #[test]
    fn metrics_layer_outbound_http_request_failure_paths() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();

        let failures = [
            ("timeout", OUTBOUND_HTTP_RESULT_TIMEOUT),
            ("connect_error", OUTBOUND_HTTP_RESULT_CONNECT_ERROR),
            ("request_error", OUTBOUND_HTTP_RESULT_REQUEST_ERROR),
            ("parse_error", OUTBOUND_HTTP_RESULT_PARSE_ERROR),
        ];

        for (label, result) in failures {
            let url = format!("/api/fail/{label}");
            let before_counter = prometheus::OUTBOUND_HTTP_REQUESTS_TOTAL
                .with_label_values(&[&url, result])
                .get();
            let before_hist = prometheus::OUTBOUND_HTTP_REQUEST_DURATION_SECONDS
                .with_label_values(&[&url])
                .get_sample_count();
            with_metrics_layer(|| {
                tracing::info!(
                    event = OUTBOUND_HTTP_REQUEST,
                    url = url.as_str(),
                    result = result,
                    duration_seconds = 0.1_f64
                );
            });
            assert!(
                prometheus::OUTBOUND_HTTP_REQUESTS_TOTAL
                    .with_label_values(&[&url, result])
                    .get()
                    > before_counter,
                "OUTBOUND_HTTP_REQUESTS_TOTAL{{result={result}}} should increment"
            );
            assert!(
                prometheus::OUTBOUND_HTTP_REQUEST_DURATION_SECONDS
                    .with_label_values(&[&url])
                    .get_sample_count()
                    > before_hist,
                "OUTBOUND_HTTP_REQUEST_DURATION_SECONDS sample count should increase for result={result}"
            );
        }
    }

    /// 测试场景：发送未注册的 metrics 事件名 → 验证 `MetricsLayer` 不更新任何指标 → 预期正常返回不 panic
    #[test]
    fn metrics_layer_ignores_unknown_event() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        with_metrics_layer(|| {
            tracing::info!(event = "unknown_event");
        });
    }

    /// 测试场景：发送不含 event 字段的普通日志事件 → 验证指标计数器不变 → 预期 before == after
    #[test]
    fn metrics_layer_ignores_event_without_event_field() {
        let _guard = METRICS_TEST_LOCK.lock().unwrap();
        let before = prometheus::HTTP_REQUESTS_TOTAL
            .with_label_values(&["GET", "/health", "200"])
            .get();
        with_metrics_layer(|| {
            tracing::info!("纯日志事件，无 event 字段");
        });
        let after = prometheus::HTTP_REQUESTS_TOTAL
            .with_label_values(&["GET", "/health", "200"])
            .get();
        assert_eq!(after, before, "不含 event 字段的事件不应触发指标更新");
    }

    /// 验证 `on_event` 内的 `event_name` 空检查能拦截不含 `event` 字段的事件，
    /// 防止 unknown 分支的 `tracing::debug!` 重新进入 `on_event` 形成递归。
    ///
    /// 构造一个不带 filter 的 MetricsLayer，发一个 unknown metrics 事件触发 debug
    /// 日志。该 debug 事件无 `event` 字段，`event_name` 为空会触发提前返回，
    /// 递归链被切断，测试正常返回即证明无栈溢出。
    #[test]
    fn event_name_check_prevents_recursion_without_filter() {
        use tracing_subscriber::layer::SubscriberExt;

        let _guard = METRICS_TEST_LOCK.lock().unwrap();

        let subscriber = tracing_subscriber::registry().with(MetricsLayer::new());

        tracing::dispatcher::with_default(&tracing::dispatcher::Dispatch::new(subscriber), || {
            tracing::info!(event = "unknown_event");
        });
    }
}
