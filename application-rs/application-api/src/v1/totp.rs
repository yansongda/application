use salvo::{Depot, Request, handler};

use crate::request::Validator;
use crate::request::totp::{
    CreateRequest, DeleteRequest, DetailRequest, DetailResponse, EditIssuerRequest,
    EditUsernameRequest, SortRequest,
};
use crate::response::Resp;
use crate::response::Response;
use crate::service;
use application_database::account::access_token::AccessToken;
use application_kernel::result::ErrorCode;

#[handler]
pub async fn sort(request: &mut Request, depot: &mut Depot) -> Resp<()> {
    let access_token = depot
        .obtain::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<SortRequest>().await?;
    let items = params.validate()?;

    service::totp::sort(access_token, items).await?;

    Ok(Response::success(()))
}

#[handler]
pub async fn all(depot: &mut Depot) -> Resp<Vec<DetailResponse>> {
    let access_token = depot
        .obtain::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    Ok(Response::success(service::totp::all(access_token).await?))
}

#[handler]
pub async fn detail(request: &mut Request, depot: &mut Depot) -> Resp<DetailResponse> {
    let access_token = depot
        .obtain::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<DetailRequest>().await?;

    Ok(Response::success(
        service::totp::detail(access_token, params.validate()?).await?,
    ))
}

#[handler]
pub async fn create(request: &mut Request, depot: &mut Depot) -> Resp<DetailResponse> {
    let access_token = depot
        .obtain::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<CreateRequest>().await?;

    Ok(Response::success(
        service::totp::create(access_token, params.validate()?).await?,
    ))
}

#[handler]
pub async fn edit_issuer(request: &mut Request, depot: &mut Depot) -> Resp<()> {
    let access_token = depot
        .obtain::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<EditIssuerRequest>().await?;

    service::totp::edit_issuer(access_token, params.validate()?).await?;

    Ok(Response::success(()))
}

#[handler]
pub async fn edit_username(request: &mut Request, depot: &mut Depot) -> Resp<()> {
    let access_token = depot
        .obtain::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<EditUsernameRequest>().await?;

    service::totp::edit_username(access_token, params.validate()?).await?;

    Ok(Response::success(()))
}

#[handler]
pub async fn delete(request: &mut Request, depot: &mut Depot) -> Resp<()> {
    let access_token = depot
        .obtain::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<DeleteRequest>().await?;

    service::totp::delete(access_token, params.validate()?).await?;

    Ok(Response::success(()))
}
