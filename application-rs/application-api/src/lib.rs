use crate::middleware::{catcher, request_logger, tracing_id};
use application_kernel::config::G_CONFIG;
use salvo::catcher::Catcher;
use salvo::compression::{Compression, CompressionLevel};
use salvo::cors::{AllowOrigin, Cors};
use salvo::http::Method;
use salvo::timeout::Timeout;
use salvo::{Router, Service};
use std::net::{IpAddr, SocketAddr};
use std::str::FromStr;
use std::time::Duration;

pub mod middleware;
pub mod request;
pub mod response;
pub mod routes;
pub mod service;
pub mod v1;

pub struct App;

impl App {
    /// # Panics
    ///
    /// 当 `G_CONFIG.bin_api.listen` 不是合法的 IP 地址时 panic。此为启动期配置错误，
    /// 预期 fail-fast。
    pub fn listen() -> SocketAddr {
        let api_config = &G_CONFIG.bin_api;

        let listen = api_config.listen.as_str();
        let port = api_config.port;

        #[allow(clippy::expect_used)]
        SocketAddr::from((
            IpAddr::from_str(listen).expect("API 监听地址格式无效"),
            port,
        ))
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
