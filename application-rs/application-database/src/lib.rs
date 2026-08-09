use application_kernel::config::{Database, G_CONFIG};
use application_kernel::result::{ErrorCode, Result};
use sqlx::MySqlPool;
use sqlx::mysql::{MySqlConnectOptions, MySqlPoolOptions};
use std::collections::HashMap;
use std::str::FromStr;
use std::sync::LazyLock;
use std::time::Duration;
use tracing::error;

mod macros;

pub mod account;
pub mod tool;

/// 携带名称的数据库连接池引用。
///
/// 由 [`Pool::mysql`] 返回，供 SQL 宏内部解构后获取 pool 名称用于指标 label。
pub struct PoolRef<'a> {
    pub name: &'a str,
    pub pool: &'a MySqlPool,
}

pub struct Pool;

static G_POOL_MYSQL: LazyLock<HashMap<&'static str, MySqlPool>> = LazyLock::new(|| {
    let databases = &G_CONFIG.databases;

    let mut mysql: HashMap<&'static str, MySqlPool> = HashMap::new();

    for database in databases {
        if database.1.url.starts_with("mysql://") {
            mysql.insert(database.0, Pool::connect_mysql(database.1));
        }
    }

    mysql
});

impl Pool {
    pub fn mysql(pool: &str) -> Result<PoolRef<'_>> {
        let p = G_POOL_MYSQL.get(pool).ok_or_else(|| {
            error!("获取数据库连接失败: {}", pool);

            ErrorCode::InternalDatabaseAcquire
        })?;

        Ok(PoolRef {
            name: pool,
            pool: p,
        })
    }

    fn connect_mysql(config: &Database) -> MySqlPool {
        let connection_options =
            MySqlConnectOptions::from_str(config.url.as_str()).expect("数据库 URL 格式无效");

        MySqlPoolOptions::new()
            .acquire_timeout(Duration::from_secs(config.acquire_timeout))
            .min_connections(config.min_connections)
            .max_connections(config.max_connections)
            .idle_timeout(Duration::from_secs(config.idle_timeout))
            .connect_lazy_with(connection_options)
    }
}
