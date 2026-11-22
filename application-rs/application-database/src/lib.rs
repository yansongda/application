use application_kernel::config::{Database, G_CONFIG};
use application_kernel::result::{ErrorCode, Result};
use sqlx::SqlitePool;
use sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous};
use std::collections::HashMap;
use std::str::FromStr;
use std::sync::LazyLock;
use std::time::Duration;
use tracing::error;

mod macros;

pub mod account;
pub mod id;
pub mod tool;

/// 携带名称的数据库连接池引用。
///
/// 由 [`Pool::get`] 返回，供 SQL 宏内部解构后获取 pool 名称用于指标 label。
pub struct PoolRef<'a> {
    pub name: &'a str,
    pub pool: &'a SqlitePool,
}

pub struct Pool;

static G_POOL_SQLITE: LazyLock<HashMap<&'static str, SqlitePool>> = LazyLock::new(|| {
    G_CONFIG
        .databases
        .iter()
        .filter(|database| database.1.url.starts_with("sqlite:"))
        .map(|database| (database.0.as_str(), Pool::connect(database.1)))
        .collect()
});

impl Pool {
    pub fn get(pool: &str) -> Result<PoolRef<'_>> {
        let p = G_POOL_SQLITE.get(pool).ok_or_else(|| {
            error!("获取数据库连接失败: {}", pool);

            ErrorCode::InternalDatabaseAcquire
        })?;

        Ok(PoolRef {
            name: pool,
            pool: p,
        })
    }

    /// 启动期自检：确保每个已配置的库都能取到可用连接。
    ///
    /// 数据库文件缺失（`create_if_missing = false`）或表未初始化时在此处 fail-fast，
    /// 避免带着坏连接对外提供服务。
    pub async fn check() -> Result<()> {
        for (name, pool) in G_POOL_SQLITE.iter() {
            sqlx::query("select 1").execute(pool).await.map_err(|e| {
                error!("数据库自检失败: pool = {}, err = {:?}", name, e);

                ErrorCode::InternalDatabaseAcquire
            })?;
        }

        Ok(())
    }

    fn connect(config: &Database) -> SqlitePool {
        #[allow(clippy::expect_used)]
        let options = SqliteConnectOptions::from_str(config.url.as_str())
            .expect("数据库 URL 格式无效")
            // WAL：允许读写并发，单写者阻塞时间由 busy_timeout 兜底
            .journal_mode(SqliteJournalMode::Wal)
            .synchronous(SqliteSynchronous::Normal)
            // 缺库直接报错，不静默创建空库
            .create_if_missing(false)
            // 复用 acquire_timeout 作为 SQLite 的写锁等待时长
            .busy_timeout(Duration::from_secs(config.acquire_timeout));

        SqlitePoolOptions::new()
            .min_connections(config.min_connections)
            .max_connections(config.max_connections)
            .idle_timeout(Duration::from_secs(config.idle_timeout))
            .connect_lazy_with(options)
    }
}
