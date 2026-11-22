use application_api::App;
use application_database::Pool;
use application_kernel::config::G_CONFIG;
use application_kernel::logger::Logger;
use salvo::prelude::TcpListener;
use salvo::{Listener, Server};
use tracing::error;

#[tokio::main]
async fn main() {
    let _logger = Logger::init(G_CONFIG.bin_api.debug);

    // 数据库文件缺失或不可用时 fail-fast，避免带着坏连接对外提供服务
    if let Err(e) = Pool::check().await {
        error!("数据库自检失败, 服务退出: {}", e);

        std::process::exit(1);
    }

    let listen = App::listen();
    let service = App::router();

    let listener = TcpListener::new(listen).bind().await;

    Server::new(listener).serve(service).await;
}
