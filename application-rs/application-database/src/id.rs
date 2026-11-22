//! `u64` 与 SQLite 整数之间的显式转换。
//!
//! SQLite 只有有符号 64 位整数（`INTEGER`），且 sqlx 未为 `u64` 实现 `Encode`，
//! 因此凡是需要绑定到 SQL 语句的 `u64` 都必须经由本模块转换。

use application_kernel::result::{ErrorCode, Result};

/// 把 `u64` 主键/外键转换为可绑定的 `i64`。
///
/// 迁移时 id 已重新编号为 1..N，正常不会越界；越界说明数据异常，返回 `9907`。
pub fn bind(value: u64) -> Result<i64> {
    i64::try_from(value).map_err(|_| ErrorCode::InternalDatabaseDataInvalid)
}

/// 把 `last_insert_rowid()` 返回值还原为 `u64`。
pub fn from_rowid(value: i64) -> Result<u64> {
    u64::try_from(value).map_err(|_| ErrorCode::InternalDatabaseDataInvalid)
}
