use chrono::{DateTime, Local};
use config::{self, Config as C, Environment, File};
use serde::Deserialize;
use std::collections::HashMap;
use std::sync::LazyLock;

pub static G_CONFIG: LazyLock<Config> = LazyLock::new(|| {
    #[allow(clippy::expect_used)]
    let config = C::builder()
        .add_source(File::with_name("./config.toml").required(false))
        .add_source(
            Environment::with_prefix("APP")
                .try_parsing(true)
                .separator("__")
                .convert_case(config::Case::Kebab),
        )
        .build()
        .expect("加载配置失败");

    #[allow(clippy::expect_used)]
    config.try_deserialize::<Config>().expect("解析配置失败")
});

#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields, rename_all = "kebab-case")]
pub struct Config {
    pub name: String,
    pub bin_api: BinApi,
    #[serde(default)]
    pub databases: HashMap<String, Database>,
    pub short_url: ShortUrl,
    pub access_token: AccessToken,
    pub http: Http,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            name: "application-rs".to_string(),
            bin_api: BinApi::default(),
            databases: HashMap::new(),
            short_url: ShortUrl::default(),
            access_token: AccessToken::default(),
            http: Http::default(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields, rename_all = "kebab-case")]
pub struct BinApi {
    pub listen: String,
    pub port: u16,
    pub debug: bool,
}

impl Default for BinApi {
    fn default() -> Self {
        Self {
            listen: "0.0.0.0".to_string(),
            port: 8080,
            debug: false,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields, rename_all = "kebab-case")]
pub struct Database {
    pub url: String,
    pub max_connections: u32,
    pub min_connections: u32,
    pub acquire_timeout: u64,
    pub idle_timeout: u64,
}

impl Default for Database {
    fn default() -> Self {
        Self {
            url: "mysql://root:root@127.0.0.1:3306/test".to_string(),
            max_connections: 20,
            min_connections: 2,
            acquire_timeout: 3,
            idle_timeout: 300,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields, rename_all = "kebab-case")]
pub struct ShortUrl {
    pub domain: String,
}

impl Default for ShortUrl {
    fn default() -> Self {
        Self {
            domain: "https://u.ysdor.cn".to_string(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields, rename_all = "kebab-case")]
pub struct AccessToken {
    pub expired_in: u32,
    pub refresh_expired_in: u32,
}

impl Default for AccessToken {
    fn default() -> Self {
        Self {
            expired_in: 3600,
            refresh_expired_in: 86400 * 30,
        }
    }
}

impl AccessToken {
    pub fn get_expired_at(&self) -> DateTime<Local> {
        Local::now() + chrono::Duration::seconds(i64::from(self.expired_in))
    }

    pub fn get_refresh_expired_at(&self) -> DateTime<Local> {
        Local::now() + chrono::Duration::seconds(i64::from(self.refresh_expired_in))
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields, rename_all = "kebab-case")]
pub struct Http {
    pub connect_timeout_secs: u64,
    pub timeout_secs: u64,
    pub pool_idle_timeout_secs: u64,
    pub pool_max_idle_per_host: usize,
    pub tcp_keepalive_secs: u64,
}

impl Default for Http {
    fn default() -> Self {
        Self {
            connect_timeout_secs: 1,
            timeout_secs: 3,
            pool_idle_timeout_secs: 30,
            pool_max_idle_per_host: 8,
            tcp_keepalive_secs: 60,
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
    use config::{Config as ConfigBuilder, FileFormat};

    fn build_config_from_toml(toml: &str) -> Result<Config, config::ConfigError> {
        ConfigBuilder::builder()
            .add_source(File::from_str(toml, FileFormat::Toml))
            .build()?
            .try_deserialize()
    }

    /// 测试场景：提供完整 [bin-api] 配置 → 验证反序列化与默认值覆盖 → 预期 port=9090, debug=true
    #[test]
    fn bin_api_default_serde_works() {
        let toml = r#"
            [bin-api]
            port = 9090
            debug = true
            listen = "0.0.0.0"
        "#;
        let cfg = build_config_from_toml(toml).expect("反序列化应成功");
        let bin = &cfg.bin_api;
        assert_eq!(bin.port, 9090);
        assert!(bin.debug);
        assert_eq!(bin.listen, "0.0.0.0");
    }

    /// 测试场景：[bin-api] 段包含未声明字段 → 验证 `deny_unknown_fields` 生效 → 预期反序列化返回 `ConfigError`
    #[test]
    fn bin_api_extra_field_rejected() {
        let toml = r#"
            [bin-api]
            port = 8016
            extra_field = 1
        "#;
        let result = build_config_from_toml(toml);
        assert!(result.is_err(), "含未声明字段应返回 ConfigError");
    }

    /// 测试场景：使用 `Config::default()` → 验证 `bin_api` 字段被默认结构填充 → 预期 port=8080, debug=false, listen=0.0.0.0
    #[test]
    fn config_default_seeds_bin_api() {
        let cfg = Config::default();
        let bin = &cfg.bin_api;
        assert_eq!(bin.port, 8080);
        assert!(!bin.debug);
        assert_eq!(bin.listen, "0.0.0.0");
    }

    /// 测试场景：空 TOML 字符串 → 验证 Config 反序列化成功且 `bin_api` 取默认值 → 预期 port=8080
    #[test]
    fn config_with_empty_bin_api_still_deserializes() {
        let cfg = build_config_from_toml("").expect("空 TOML 反序列化应成功");
        let bin = &cfg.bin_api;
        assert_eq!(bin.port, 8080);
    }

    /// 测试场景：TOML 含未声明字段 → 验证 `deny_unknown_fields` 生效 → 预期反序列化返回 `ConfigError`
    #[test]
    fn config_extra_field_rejected() {
        let toml = r#"
            name = "test"
            extra_field = 1
        "#;
        let result = build_config_from_toml(toml);
        assert!(result.is_err(), "含未声明字段应返回 ConfigError");
    }

    /// 测试场景：TOML 含 `[databases.default]` 段 → 验证 Config 反序列化成功且 databases 非空 → 预期 databases 包含 "default" 键
    #[test]
    fn config_with_databases_section_deserializes() {
        let toml = r#"
            [databases.default]
            url = "mysql://user:pass@host:3306/db"
            max-connections = 10
            min-connections = 1
            acquire-timeout = 5
            idle-timeout = 600
        "#;
        let cfg = build_config_from_toml(toml).expect("反序列化应成功");
        assert!(cfg.databases.contains_key("default"));
        let db = cfg.databases.get("default").expect("default 连接应存在");
        assert_eq!(db.url, "mysql://user:pass@host:3306/db");
        assert_eq!(db.max_connections, 10);
        assert_eq!(db.min_connections, 1);
        assert_eq!(db.acquire_timeout, 5);
        assert_eq!(db.idle_timeout, 600);
    }

    /// 测试场景：TOML 缺少 `[databases]` 段 → 验证 `#[serde(default)]` 生效 → 预期反序列化成功且 databases 为空 HashMap
    #[test]
    fn config_databases_missing_section_uses_default() {
        let toml = r#"
            name = "test"
        "#;
        let cfg = build_config_from_toml(toml).expect("反序列化应成功");
        assert!(
            cfg.databases.is_empty(),
            "databases 段缺失时应使用默认空 HashMap"
        );
    }

    /// 测试场景：[short-url] 段包含未声明字段 → 验证 `deny_unknown_fields` 生效 → 预期反序列化返回 `ConfigError`
    #[test]
    fn short_url_extra_field_rejected() {
        let toml = r#"
            [short-url]
            domain = "https://example.com"
            extra_field = 1
        "#;
        let result = build_config_from_toml(toml);
        assert!(result.is_err(), "含未声明字段应返回 ConfigError");
    }

    /// 测试场景：[access-token] 段包含未声明字段 → 验证 `deny_unknown_fields` 生效 → 预期反序列化返回 `ConfigError`
    #[test]
    fn access_token_extra_field_rejected() {
        let toml = r#"
            [access-token]
            expired-in = 3600
            extra_field = 1
        "#;
        let result = build_config_from_toml(toml);
        assert!(result.is_err(), "含未声明字段应返回 ConfigError");
    }

    /// 测试场景：[http] 段提供完整值 -> 验证覆盖默认 -> 预期 2/5/60/16/120
    #[test]
    fn http_section_overrides_defaults() {
        let toml = r#"
            [http]
            connect-timeout-secs = 2
            timeout-secs = 5
            pool-idle-timeout-secs = 60
            pool-max-idle-per-host = 16
            tcp-keepalive-secs = 120
        "#;
        let cfg = build_config_from_toml(toml).expect("反序列化应成功");
        assert_eq!(cfg.http.connect_timeout_secs, 2);
        assert_eq!(cfg.http.timeout_secs, 5);
        assert_eq!(cfg.http.pool_idle_timeout_secs, 60);
        assert_eq!(cfg.http.pool_max_idle_per_host, 16);
        assert_eq!(cfg.http.tcp_keepalive_secs, 120);
    }

    /// 测试场景：缺 [http] 段 -> 验证默认值 -> 预期 1/3/30/8/60
    #[test]
    fn http_section_missing_uses_default() {
        let cfg = build_config_from_toml("").expect("空 TOML 反序列化应成功");
        assert_eq!(cfg.http.connect_timeout_secs, 1);
        assert_eq!(cfg.http.timeout_secs, 3);
        assert_eq!(cfg.http.pool_idle_timeout_secs, 30);
        assert_eq!(cfg.http.pool_max_idle_per_host, 8);
        assert_eq!(cfg.http.tcp_keepalive_secs, 60);
    }

    /// 测试场景：[http] 含未声明字段 -> deny_unknown_fields -> ConfigError
    #[test]
    fn http_extra_field_rejected() {
        let toml = r#"
            [http]
            connect-timeout-secs = 1
            extra_field = 1
        "#;
        let result = build_config_from_toml(toml);
        assert!(result.is_err(), "含未声明字段应返回 ConfigError");
    }

    /// 测试场景：`Database::default()` → 验证各字段均为默认值
    #[test]
    fn database_default_seeds_fields() {
        let db = Database::default();
        assert_eq!(db.url, "mysql://root:root@127.0.0.1:3306/test");
        assert_eq!(db.max_connections, 20);
        assert_eq!(db.min_connections, 2);
        assert_eq!(db.acquire_timeout, 3);
        assert_eq!(db.idle_timeout, 300);
    }
}
