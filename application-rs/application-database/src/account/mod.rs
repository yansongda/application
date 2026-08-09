use serde::de::Visitor;
use serde::{Deserialize, Deserializer, Serialize};
use sqlx::encode::IsNull;
use sqlx::error::BoxDynError;
use sqlx::mysql::{MySqlTypeInfo, MySqlValueRef};
use sqlx::{Decode, Encode, MySql, Type};
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

impl Type<MySql> for Platform {
    fn type_info() -> <MySql as sqlx::Database>::TypeInfo {
        <&str as Type<MySql>>::type_info()
    }

    fn compatible(_: &MySqlTypeInfo) -> bool {
        true
    }
}

impl sqlx::Encode<'_, MySql> for Platform {
    fn encode_by_ref(&self, buf: &mut Vec<u8>) -> Result<IsNull, BoxDynError> {
        <&str as Encode<MySql>>::encode(self.into(), buf)
    }
}

impl sqlx::Decode<'_, MySql> for Platform {
    fn decode(value: MySqlValueRef<'_>) -> Result<Self, BoxDynError> {
        let s = <&str as Decode<MySql>>::decode(value)?;

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
