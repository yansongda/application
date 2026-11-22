use serde::de::Visitor;
use serde::{Deserialize, Deserializer, Serialize};
use sqlx::encode::IsNull;
use sqlx::error::BoxDynError;
use sqlx::sqlite::{SqliteArgumentsBuffer, SqliteTypeInfo, SqliteValueRef};
use sqlx::{Decode, Encode, Sqlite, Type};
use std::fmt::{Display, Formatter};

pub mod access_token;
pub mod refresh_token;
pub mod third_config;
pub mod third_user;
pub mod user;

#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub enum Platform {
    Wechat,
    Huawei,
    Unsupported,
}

impl Display for Platform {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", <&Platform as Into<&str>>::into(self))
    }
}

impl From<&Platform> for &str {
    fn from(v: &Platform) -> Self {
        match v {
            Platform::Wechat => "wechat",
            Platform::Huawei => "huawei",
            Platform::Unsupported => "unsupported",
        }
    }
}

impl From<&str> for Platform {
    fn from(v: &str) -> Self {
        match v {
            "wechat" => Platform::Wechat,
            "huawei" => Platform::Huawei,
            _ => Platform::Unsupported,
        }
    }
}

impl From<String> for Platform {
    fn from(v: String) -> Self {
        Self::from(v.to_lowercase().as_str())
    }
}

impl From<Platform> for String {
    fn from(v: Platform) -> Self {
        v.to_string()
    }
}

impl Type<Sqlite> for Platform {
    fn type_info() -> SqliteTypeInfo {
        <&str as Type<Sqlite>>::type_info()
    }
}

impl sqlx::Encode<'_, Sqlite> for Platform {
    fn encode_by_ref(&self, buf: &mut SqliteArgumentsBuffer) -> Result<IsNull, BoxDynError> {
        <&str as Encode<Sqlite>>::encode(self.into(), buf)
    }
}

impl sqlx::Decode<'_, Sqlite> for Platform {
    fn decode(value: SqliteValueRef<'_>) -> Result<Self, BoxDynError> {
        let s = <&str as Decode<Sqlite>>::decode(value)?;

        Ok(s.into())
    }
}

struct PlatformVisitor;

impl Visitor<'_> for PlatformVisitor {
    type Value = Platform;

    fn expecting(&self, formatter: &mut Formatter) -> std::fmt::Result {
        formatter.write_str("反序列化失败，值应该为 string/str.")
    }

    fn visit_str<E>(self, v: &str) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        Ok(v.to_owned().into())
    }

    fn visit_string<E>(self, v: String) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        Ok(v.into())
    }
}

impl<'de> Deserialize<'de> for Platform {
    fn deserialize<D>(deserializer: D) -> Result<Platform, D::Error>
    where
        D: Deserializer<'de>,
    {
        deserializer.deserialize_any(PlatformVisitor)
    }
}
