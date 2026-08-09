use crate::request::Validator;
use crate::request::user::{
    DetailResponse, EditAvatarRequest, EditNicknameRequest, EditPhoneRequest, EditSloganRequest,
};
use crate::response::Resp;
use crate::response::Response;
use crate::service;
use application_database::account::access_token::AccessToken;
use application_kernel::result::ErrorCode;
use salvo::{Depot, Request, handler};

#[handler]
pub async fn detail(depot: &mut Depot) -> Resp<DetailResponse> {
    let access_token = depot
        .get_typed::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let user = service::user::detail(access_token.user_id).await?;

    Ok(Response::success(user.into()))
}

#[handler]
pub async fn edit_avatar(request: &mut Request, depot: &mut Depot) -> Resp<()> {
    let access_token = depot
        .get_typed::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<EditAvatarRequest>().await?;

    service::user::update_avatar(access_token, params.validate()?.as_str()).await?;

    Ok(Response::success(()))
}

#[handler]
pub async fn edit_nickname(request: &mut Request, depot: &mut Depot) -> Resp<()> {
    let access_token = depot
        .get_typed::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<EditNicknameRequest>().await?;

    service::user::update_nickname(access_token, params.validate()?.as_str()).await?;

    Ok(Response::success(()))
}

#[handler]
pub async fn edit_slogan(request: &mut Request, depot: &mut Depot) -> Resp<()> {
    let access_token = depot
        .get_typed::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<EditSloganRequest>().await?;

    service::user::update_slogan(access_token, params.validate()?.as_str()).await?;

    Ok(Response::success(()))
}

#[handler]
pub async fn edit_phone(request: &mut Request, depot: &mut Depot) -> Resp<()> {
    let access_token = depot
        .get_typed::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<EditPhoneRequest>().await?;

    service::user::update_phone(access_token, params.validate()?.as_str()).await?;

    Ok(Response::success(()))
}

#[handler]
pub async fn delete(depot: &mut Depot) -> Resp<()> {
    let access_token = depot
        .get_typed::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    service::user::delete(access_token).await?;

    Ok(Response::success(()))
}
