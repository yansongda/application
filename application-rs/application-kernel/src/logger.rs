use tracing::level_filters::LevelFilter;
use tracing::{Event, Subscriber};
use tracing_appender::non_blocking::{NonBlockingBuilder, WorkerGuard};
use tracing_subscriber::filter;
use tracing_subscriber::fmt::{FmtContext, FormatEvent, FormatFields, format};
use tracing_subscriber::layer::{Context, Filter, Layer, SubscriberExt};
use tracing_subscriber::registry::{LookupSpan, Scope};
use tracing_subscriber::util::SubscriberInitExt;

use crate::listeners::metrics::{MetricsFilter, MetricsLayer};

/// 写入 span extensions 的请求 ID 标记，由 [`TracingFormatter`] 读取并拼到日志行首。
pub struct TracingId(pub String);

impl TracingId {
    /// 把 `request_id` 写入 `span` 的 extensions，供 [`TracingFormatter`] 在日志行首输出。
    ///
    /// 当 dispatcher 背后不是 `tracing_subscriber::Registry`（例如测试中的 stub subscriber）
    /// 时静默 no-op，调用方无需处理降级路径，不会 panic。
    pub fn attach(span: &tracing::Span, request_id: &str) {
        span.with_subscriber(|(id, dispatch)| {
            if let Some(sub) = dispatch.downcast_ref::<tracing_subscriber::Registry>()
                && let Some(span_ref) = sub.span(id)
            {
                span_ref
                    .extensions_mut()
                    .insert(TracingId(request_id.to_string()));
            }
        });
    }
}

/// 只放行含 `message` 字段（人类可读信息）的事件的过滤器。
///
/// 纯 metrics 事件（只有 `event` 字段、无 `message`）由 `MetricsLayer` 消费，
/// 不应写入日志。此过滤器确保 `fmt::layer` 只输出人类可读的日志行。
struct HumanReadableFilter;

impl<S> Filter<S> for HumanReadableFilter
where
    S: Subscriber,
{
    // `enabled` 是 `Filter` trait 的必需方法（无默认实现）。
    fn enabled(&self, _: &tracing::Metadata<'_>, _: &Context<'_, S>) -> bool {
        true
    }

    fn event_enabled(&self, event: &Event<'_>, _ctx: &Context<'_, S>) -> bool {
        event.metadata().fields().field("message").is_some()
    }
}

#[derive(Debug, Clone)]
struct TracingFormatter;

impl<S, N> FormatEvent<S, N> for TracingFormatter
where
    S: Subscriber + for<'a> LookupSpan<'a>,
    N: for<'a> FormatFields<'a> + 'static,
{
    fn format_event(
        &self,
        ctx: &FmtContext<'_, S, N>,
        mut writer: format::Writer<'_>,
        event: &Event<'_>,
    ) -> std::fmt::Result {
        write!(
            &mut writer,
            "{}|{}|",
            chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.6f"),
            event.metadata().level()
        )?;

        for span in ctx.event_scope().into_iter().flat_map(Scope::from_root) {
            if let Some(tracing_id) = span.extensions().get::<TracingId>() {
                write!(writer, "{}|", tracing_id.0)?;
                break;
            }
        }

        ctx.format_fields(writer.by_ref(), event)?;
        writeln!(writer)
    }
}

/// 日志单行最大字节数，超出由 [`truncate_for_log`] 截断。
pub const MAX_LOG_LENGTH: usize = 1024;

/// UTF-8 边界安全的字节日志截断。
///
/// `data` 字节长度 ≤ [`MAX_LOG_LENGTH`] 时原样返回；超过时只对前
/// [`MAX_LOG_LENGTH`] 字节做 `from_utf8_lossy`（避免对超大 body 构造完整
/// String），在 UTF-8 字符边界处截断并附加 `...[truncated, N bytes]` 后缀
///（`N` 为原始 `data` 的字节数）。
pub fn truncate_for_log(data: &[u8]) -> String {
    if data.len() <= MAX_LOG_LENGTH {
        return String::from_utf8_lossy(data).into_owned();
    }

    let s = String::from_utf8_lossy(&data[..MAX_LOG_LENGTH]);

    let mut end = MAX_LOG_LENGTH;
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }

    format!("{}...[truncated, {} bytes]", &s[..end], data.len())
}

/// 全局 tracing subscriber 持有者。
///
/// 必须将 [`Logger::init`] 的返回值绑定到与进程生命周期一致的变量（例如
/// `let _logger = Logger::init();`），否则 `WorkerGuard` 立即 drop，后台 writer
/// 线程退出，日志会丢失。
#[must_use = "Logger must be kept alive for the lifetime of the program"]
pub struct Logger {
    _guard: WorkerGuard,
}

impl Logger {
    /// 初始化全局 tracing subscriber 并返回持有 `WorkerGuard` 的 [`Logger`]。
    ///
    /// 日志级别由传入的 `debug` 参数决定：`true` -> DEBUG，否则 INFO。
    pub fn init(debug: bool) -> Self {
        let (non_blocking, guard) = NonBlockingBuilder::default().finish(std::io::stdout());

        tracing_subscriber::registry()
            .with(Self::get_filter_target(debug))
            .with(
                tracing_subscriber::fmt::layer()
                    .event_format(TracingFormatter)
                    .with_writer(non_blocking)
                    .with_filter(HumanReadableFilter),
            )
            .with(MetricsLayer::new().with_filter(MetricsFilter))
            .try_init()
            .ok();

        Logger { _guard: guard }
    }

    fn get_filter_target(debug: bool) -> filter::Targets {
        let level = if debug {
            LevelFilter::DEBUG
        } else {
            LevelFilter::INFO
        };

        filter::Targets::new().with_default(level)
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

    /// 测试场景：短字节输入 -> 验证 truncate_for_log 不截断 -> 预期返回原字符串
    #[test]
    fn truncate_for_log_short_bytes_unchanged() {
        assert_eq!(truncate_for_log(b"hello world"), "hello world");
    }

    /// 测试场景：空字节输入 -> 验证 truncate_for_log 不截断 -> 预期返回空字符串
    #[test]
    fn truncate_for_log_empty_bytes_unchanged() {
        assert_eq!(truncate_for_log(b""), "");
    }

    /// 测试场景：超长字节输入 -> 验证 truncate_for_log 截断并附加字节数后缀 -> 预期长度小于原长度且包含 [truncated
    #[test]
    fn truncate_for_log_long_bytes_truncated() {
        let data = b"a".repeat(MAX_LOG_LENGTH + 100);
        let truncated = truncate_for_log(&data);
        assert!(truncated.len() < data.len());
        assert!(truncated.contains("[truncated"));
        assert!(
            truncated.contains(&format!("{} bytes", data.len())),
            "应包含原始字节数"
        );
        assert!(truncated.starts_with(&"a".repeat(MAX_LOG_LENGTH)));
    }

    /// 测试场景：字节长度恰好等于 MAX_LOG_LENGTH -> 验证不截断 -> 预期返回原字符串且不含 truncated
    #[test]
    fn truncate_for_log_at_exact_boundary_unchanged() {
        let data = b"a".repeat(MAX_LOG_LENGTH);
        let result = truncate_for_log(&data);
        assert_eq!(result.len(), MAX_LOG_LENGTH);
        assert!(!result.contains("truncated"));
    }

    /// 测试场景：超长中文字节输入 -> 验证 truncate_for_log 在 UTF-8 字符边界处截断 -> 预期不产生非法 UTF-8 且包含 [truncated
    #[test]
    fn truncate_for_log_utf8_boundary_safe() {
        let data = "中".repeat(500).into_bytes();
        let truncated = truncate_for_log(&data);
        assert!(truncated.contains("[truncated"));
        assert!(truncated.chars().count() > 0);
        let _ =
            String::from_utf8(truncated.clone().into_bytes()).expect("截断结果必须是合法 UTF-8");
        assert!(truncated.starts_with(&"中".repeat(341)));
    }

    /// 测试场景：含非法 UTF-8 字节 -> 验证 from_utf8_lossy 用 U+FFFD 替换不 panic -> 预期返回含替换符的字符串
    #[test]
    fn truncate_for_log_invalid_utf8_replaced() {
        let data = [0xFF, 0xFE, b'h', b'i'];
        let result = truncate_for_log(&data);
        assert!(result.contains('\u{FFFD}'));
        assert!(result.contains("hi"));
    }

    /// 测试场景：读取 `MAX_LOG_LENGTH` 常量 → 验证其值为 1024 → 预期等于 1024
    #[test]
    fn max_log_length_is_1024() {
        assert_eq!(MAX_LOG_LENGTH, 1024);
    }

    /// 测试场景：调用 `Logger::init(false)` → 验证返回 Logger 实例且持有 `WorkerGuard` → 预期不 panic
    #[test]
    fn logger_init_returns_logger_with_guard() {
        let _logger = Logger::init(false);
    }

    /// 测试场景：在 Registry subscriber 下调用 `TracingId::attach` → 验证 span extensions 中可读取到 `TracingId` → 预期返回 Some(true)
    #[test]
    fn attach_inserts_into_span_extensions() {
        use tracing_subscriber::Registry;
        let _guard = tracing::subscriber::set_default(Registry::default());

        let span = tracing::info_span!("test.span", request_id = "req-001");
        TracingId::attach(&span, "req-001");

        let extensions_found = span.with_subscriber(|(id, dispatch)| {
            let reg = dispatch
                .downcast_ref::<tracing_subscriber::Registry>()
                .expect("subscriber 必须是 Registry");
            let span_ref = reg.span(id).expect("span 必须存在");
            span_ref.extensions().get::<TracingId>().is_some()
        });
        assert_eq!(
            extensions_found,
            Some(true),
            "TracingId extension 必须被插入"
        );
    }

    /// 测试场景：在非 Registry subscriber 下调用 `TracingId::attach` → 验证方法静默 no-op → 预期不 panic
    #[test]
    fn attach_noop_when_subscriber_not_registry() {
        struct NoSubscriber;

        impl tracing::Subscriber for NoSubscriber {
            fn enabled(&self, _: &tracing::Metadata<'_>) -> bool {
                false
            }
            fn max_level_hint(&self) -> Option<tracing::level_filters::LevelFilter> {
                None
            }
            fn new_span(&self, _: &tracing::span::Attributes<'_>) -> tracing::span::Id {
                tracing::span::Id::from_u64(1)
            }
            fn record(&self, _: &tracing::span::Id, _: &tracing::span::Record<'_>) {}
            fn record_follows_from(&self, _: &tracing::span::Id, _: &tracing::span::Id) {}
            fn event(&self, _: &tracing::Event<'_>) {}
            fn enter(&self, _: &tracing::span::Id) {}
            fn exit(&self, _: &tracing::span::Id) {}
            fn register_callsite(
                &self,
                _: &'static tracing::Metadata<'static>,
            ) -> tracing::subscriber::Interest {
                tracing::subscriber::Interest::never()
            }
        }

        let _guard = tracing::subscriber::set_default(NoSubscriber);
        let span = tracing::info_span!("test.span");
        TracingId::attach(&span, "req-002");
    }
}
