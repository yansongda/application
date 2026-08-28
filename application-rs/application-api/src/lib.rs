use crate::middleware::{catcher, request_logger, tracing_id};
use application_kernel::config::G_CONFIG;
use salvo::catcher::Catcher;
use salvo::compression::{Compression, CompressionLevel};
use salvo::cors::{AllowOrigin, Cors};
use salvo::http::Method;
use salvo::timeout::Timeout;
use salvo::{Router, Service};
use std::net::{Ipv4Addr, SocketAddr};
use std::time::Duration;

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
