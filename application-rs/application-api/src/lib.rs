use crate::middleware::{catcher, request_logger, tracing_id};
use application_kernel::config::G_CONFIG;
use salvo::catcher::Catcher;
use salvo::compression::{Compression, CompressionLevel};
use salvo::cors::{AllowOrigin, Cors};
use salvo::http::Method;
use salvo::http::request::set_global_secure_max_size;
use salvo::timeout::Timeout;
use salvo::{Router, Service};
use std::net::{Ipv4Addr, SocketAddr};
use std::time::Duration;

pub mod backup;
pub mod middleware;
pub mod request;
pub mod response;
pub mod routes;
pub mod service;
pub mod v1;

pub struct App;

impl App {
    /// 监听地址固定为 0.0.0.0（不开放配置），端口取自 `[bin-api]` 配置。
    pub fn listen() -> SocketAddr {
        SocketAddr::from((Ipv4Addr::UNSPECIFIED, G_CONFIG.bin_api.port))
    }

    pub fn router() -> Service {
        // 备份导入的请求体包含整份加密备份（50 条上限最坏约 75 KB），Salvo 默认 64 KiB 不足；
        // 该上限对进程内所有读取 body 的接口生效（原 64 KiB 全局限值随之放宽）。
        set_global_secure_max_size(512 * 1024);

        let router = Router::new()
            .push(routes::health())
            .push(routes::metrics())
            .push(routes::api_v1());

        Service::new(router)
            .hoop(tracing_id)
            .hoop(
                Cors::new()
                    .allow_origin(AllowOrigin::any())
                    .allow_methods(vec![Method::GET, Method::POST, Method::DELETE])
                    .allow_headers("authorization")
                    .into_handler(),
            )
            .hoop(Timeout::new(Duration::from_secs(10)))
            .hoop(Compression::new().enable_brotli(CompressionLevel::Fastest))
            .hoop(request_logger)
            .hoop(salvo::catch_panic::CatchPanic::new())
            .catcher(Catcher::default().hoop(catcher))
    }
}
