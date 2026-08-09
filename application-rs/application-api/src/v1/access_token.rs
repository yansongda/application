use crate::request::Validator;
use crate::request::access_token::{
    LoginRefreshRequest, LoginRefreshResponse, LoginRequest, LoginResponse,
};
use crate::response::{Resp, Response};
use crate::service;
use salvo::{Request, handler};

#[handler]
pub async fn login(request: &mut Request) -> Resp<LoginResponse> {
    let params = request.parse_json::<LoginRequest>().await?;

    let req = params.validate()?;

    let (refresh_token, access_token) = service::access_token::login(&req).await?;

    Ok(Response::success(LoginResponse {
        access_token: access_token.access_token.clone(),
        expired_in: access_token.get_expired_in(),
        refresh_token: refresh_token.refresh_token,
    }))
}

#[handler]
pub async fn login_refresh(request: &mut Request) -> Resp<LoginRefreshResponse> {
    let params = request.parse_json::<LoginRefreshRequest>().await?;

    let req = params.validate()?;

    let (refresh_token, access_token) = service::access_token::login_refresh(&req).await?;

    Ok(Response::success(LoginRefreshResponse {
        access_token: access_token.access_token.clone(),
        expired_in: access_token.get_expired_in(),
        refresh_token: refresh_token.refresh_token,
    }))
}

#[handler]
pub async fn valid() -> Resp<()> {
    Ok(Response::success(()))
}
