use serde::Serialize;
use std::fmt::{Debug, Display, Formatter};

pub type Result<D> = std::result::Result<D, ErrorCode>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum ErrorCode {
    Success = 0,

    // 1000 系列：授权认证错误
    AuthorizationHeaderMissing = 1000,
    AuthorizationAccessTokenInvalid = 1001,
    AuthorizationInvalidFormat = 1002,
    AuthorizationPermissionUngranted = 1003,
    AuthorizationAccessTokenExpired = 1004,
    AuthorizationRefreshTokenInvalid = 1005,
    AuthorizationRefreshTokenExpired = 1006,

    // 2000 系列：参数校验错误
    ParamsJsonInvalid = 2000,
    ParamsLoginPlatformUnsupported = 2001,
    ParamsLoginCodeFormatInvalid = 2002,
    ParamsThirdUserNotFound = 2003,
    ParamsAccessTokenNotFound = 2004,
    ParamsUserNotFound = 2005,
    ParamsUserNicknameLengthInvalid = 2006,
    ParamsUserPhoneFormatInvalid = 2007,
    ParamsTotpNotFound = 2008,
    ParamsTotpParseFailed = 2009,
    ParamsTotpIdEmpty = 2010,
    ParamsTotpIssuerMaxLengthReached = 2011,
    ParamsTotpUriFormatInvalid = 2012,
    ParamsTotpUsernameFormatInvalid = 2013,
    ParamsShortlinkNotFound = 2014,
    ParamsShortlinkEmpty = 2015,
    ParamsShortlinkFormatInvalid = 2016,
    ParamsUserSloganLengthInvalid = 2017,
    ParamsUserAvatarLengthInvalid = 2018,
    ParamsThirdConfigNotFound = 2019,
    ParamsLoginPlatformThirdIdFormatInvalid = 2020,
    ParamsRefreshTokenNotFound = 2021,

    // 9800 系列：第三方服务错误
    ThirdHttpRequest = 9800,
    ThirdHttpResponse = 9801,
    ThirdHttpResponseParse = 9802,
    ThirdHttpResponseResult = 9803,

    // 9900 系列：内部/数据库错误
    InternalReadBodyFailed = 9900,
    InternalDatabaseAcquire = 9901,
    InternalDatabaseQuery = 9902,
    InternalDatabaseInsert = 9903,
    InternalDatabaseUpdate = 9904,
    InternalDatabaseDelete = 9905,
    InternalDataToAccessTokenError = 9906,
    InternalDatabaseDataInvalid = 9907,

    // 新增变体用于 catcher 中间件
    StatusNotFound = 404,
    StatusMethodNotAllowed = 405,
    UnknownError = 9999,
}

impl ErrorCode {
    pub fn message(&self) -> &'static str {
        match self {
            Self::Success => "success",
            Self::AuthorizationHeaderMissing => "认证失败: 缺少认证信息,请重新登录",
            Self::AuthorizationAccessTokenInvalid | Self::AuthorizationRefreshTokenInvalid => {
                "认证失败: 认证信息不正确,请重新登录"
            }
            Self::AuthorizationInvalidFormat => "认证失败: 认证信息格式不正确,请重新登录",
            Self::AuthorizationPermissionUngranted => "认证失败: 未授权,请勿越权使用",
            Self::AuthorizationAccessTokenExpired | Self::AuthorizationRefreshTokenExpired => {
                "认证失败: 认证信息已过期,请重新登录"
            }
            Self::ParamsJsonInvalid => "参数错误: Json 解析失败,请确认您的参数是否符合规范",
            Self::ParamsLoginPlatformUnsupported => "参数错误: platform 参数值不支持",
            Self::ParamsLoginCodeFormatInvalid => "参数错误: 登录秘钥格式错误",
            Self::ParamsThirdUserNotFound => "参数错误: 第三方平台关联用户未找到",
            Self::ParamsAccessTokenNotFound => "参数错误: Access Token 未找到",
            Self::ParamsUserNotFound => "参数错误: 用户未找到",
            Self::ParamsUserNicknameLengthInvalid => "参数错误: 昵称长度应为 1~16 之间,请正确填写",
            Self::ParamsUserPhoneFormatInvalid => "参数错误: 手机号码格式不正确,请正确填写",
            Self::ParamsTotpNotFound => "参数错误: TOTP 信息未找到",
            Self::ParamsTotpParseFailed => {
                "参数错误: TOTP 链接解析失败, 请确认是否是正确的 TOTP 链接"
            }
            Self::ParamsTotpIdEmpty => "参数错误: 详情 id 不能为空",
            Self::ParamsTotpIssuerMaxLengthReached => "参数错误: TOTP 链接不能为空",
            Self::ParamsTotpUriFormatInvalid => "参数错误: TOTP 链接格式不正确",
            Self::ParamsTotpUsernameFormatInvalid => "参数错误: TOTP 用户名格式不正确",
            Self::ParamsShortlinkNotFound => "参数错误: 短连接未找到",
            Self::ParamsShortlinkEmpty => "参数错误: URL 不能为空",
            Self::ParamsShortlinkFormatInvalid => "参数错误: URL 格式不正确",
            Self::ParamsUserSloganLengthInvalid => "参数错误: Slogan 长度应大于 3,请正确填写",
            Self::ParamsUserAvatarLengthInvalid => "参数错误: 头像格式不正确,请正确填写",
            Self::ParamsThirdConfigNotFound | Self::ParamsLoginPlatformThirdIdFormatInvalid => {
                "参数错误: 您访问的平台暂不支持,请重试或联系管理员"
            }
            Self::ParamsRefreshTokenNotFound => "参数错误: Refresh Token 未找到",
            Self::ThirdHttpRequest => "第三方错误: 第三方 API 请求出错,请联系管理员",
            Self::ThirdHttpResponse => "第三方错误: 第三方 API 响应出错,请联系管理员",
            Self::ThirdHttpResponseParse => "第三方错误: 第三方 API 响应解析出错,请联系管理员",
            Self::ThirdHttpResponseResult => "第三方错误: 第三方 API 业务结果出错,请联系管理员",
            Self::InternalReadBodyFailed => "内部错误: 读取 Body 体失败,请联系管理员",
            Self::InternalDatabaseAcquire => "内部错误: 数据库连接出现了一些问题,请联系管理员",
            Self::InternalDatabaseQuery => "内部错误: 查询数据出现了一些问题,请联系管理员",
            Self::InternalDatabaseInsert => "内部错误: 保存数据出现了一些问题,请联系管理员",
            Self::InternalDatabaseUpdate => "内部错误: 更新数据出现了一些问题,请联系管理员",
            Self::InternalDatabaseDelete => "内部错误: 删除数据出现了一些问题,请联系管理员",
            Self::InternalDataToAccessTokenError => {
                "内部错误: 生成 access_token 令牌有误,请联系管理员"
            }
            Self::InternalDatabaseDataInvalid => "内部错误: 数据库数据有误,请联系管理员",
            Self::StatusNotFound => "请求的资源不存在",
            Self::StatusMethodNotAllowed => "请求方法不被允许",
            Self::UnknownError => "内部服务异常,请稍后重试",
        }
    }

    pub fn code(&self) -> i32 {
        *self as i32
    }
}

impl Display for ErrorCode {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "[{}] {}", self.code(), self.message())
    }
}

impl std::error::Error for ErrorCode {}

#[cfg(test)]
mod tests {
    #![allow(clippy::all)]

    use super::*;

    #[test]
    fn test_error_display() {
        let err = ErrorCode::AuthorizationHeaderMissing;

        assert_eq!(err.to_string(), "[1000] 认证失败: 缺少认证信息,请重新登录");
    }

    #[test]
    fn test_error_code_ranges() {
        let cases = [
            (ErrorCode::AuthorizationAccessTokenInvalid, 1001),
            (ErrorCode::ParamsUserNotFound, 2005),
            (ErrorCode::ThirdHttpResponse, 9801),
            (ErrorCode::InternalDatabaseDelete, 9905),
        ];

        for (err, expected_code) in cases {
            assert_eq!(err.code(), expected_code);
        }
    }

    #[test]
    fn test_error_is_copy() {
        let err = ErrorCode::InternalDatabaseQuery;
        let c = err;
        let c2 = err;

        assert_eq!(c, c2);
        assert_eq!(
            c.to_string(),
            "[9902] 内部错误: 查询数据出现了一些问题,请联系管理员"
        );
    }

    #[test]
    fn test_error_implements_std_error() {
        fn assert_std_error<E: std::error::Error>() {}

        assert_std_error::<ErrorCode>();
    }

    #[test]
    fn test_auth_access_token_expired_maps_to_1004() {
        let err = ErrorCode::AuthorizationAccessTokenExpired;
        assert_eq!(err.code(), 1004);
        assert!(err.message().contains("过期"));
    }

    #[test]
    fn test_auth_refresh_token_invalid_maps_to_1005() {
        let err = ErrorCode::AuthorizationRefreshTokenInvalid;
        assert_eq!(err.code(), 1005);
        assert!(err.message().contains("不正确"));
    }

    #[test]
    fn test_auth_refresh_token_expired_maps_to_1006() {
        let err = ErrorCode::AuthorizationRefreshTokenExpired;
        assert_eq!(err.code(), 1006);
        assert!(err.message().contains("过期"));
    }

    #[test]
    fn test_auth_error_codes_are_distinguishable() {
        let cases = [
            (ErrorCode::AuthorizationAccessTokenExpired, 1004),
            (ErrorCode::AuthorizationRefreshTokenInvalid, 1005),
            (ErrorCode::AuthorizationRefreshTokenExpired, 1006),
        ];
        for (err, expected) in cases {
            assert_eq!(err.code(), expected);
        }
    }

    #[test]
    fn test_auth_access_token_expired_display_format() {
        let err = ErrorCode::AuthorizationAccessTokenExpired;
        let display = err.to_string();
        assert!(display.starts_with("[1004]"));
    }

    #[test]
    fn test_success_code_and_message() {
        let err = ErrorCode::Success;
        assert_eq!(err.code(), 0);
        assert_eq!(err.message(), "success");
    }

    #[test]
    fn test_status_not_found_code() {
        let err = ErrorCode::StatusNotFound;
        assert_eq!(err.code(), 404);
        assert_eq!(err.message(), "请求的资源不存在");
    }

    #[test]
    fn test_status_method_not_allowed_code() {
        let err = ErrorCode::StatusMethodNotAllowed;
        assert_eq!(err.code(), 405);
        assert_eq!(err.message(), "请求方法不被允许");
    }

    #[test]
    fn test_unknown_error_code() {
        let err = ErrorCode::UnknownError;
        assert_eq!(err.code(), 9999);
        assert_eq!(err.message(), "内部服务异常,请稍后重试");
    }
}
