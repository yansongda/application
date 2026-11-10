use salvo::{Depot, Request, handler};

use crate::request::Validator;
use crate::request::backup::{ExportRequest, ImportRequest, ImportResponse};
use crate::response::Resp;
use crate::response::Response;
use crate::service;
use crate::service::backup::Envelope;
use application_database::account::access_token::AccessToken;
use application_kernel::result::ErrorCode;

#[handler]
pub async fn export(request: &mut Request, depot: &mut Depot) -> Resp<Envelope> {
    let access_token = depot
        .get_typed::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<ExportRequest>().await?;
    let params = params.validate()?;

    Ok(Response::success(
        service::backup::export(access_token, &params.kind, params.password).await?,
    ))
}

#[handler]
pub async fn import(request: &mut Request, depot: &mut Depot) -> Resp<ImportResponse> {
    let access_token = depot
        .get_typed::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<ImportRequest>().await?;
    let params = params.validate()?;

    let imported =
        service::backup::import(access_token, &params.kind, params.password, params.backup).await?;

    Ok(Response::success(ImportResponse { imported }))
}
