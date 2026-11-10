use salvo::{Depot, Request, handler};

use crate::request::Validator;
use crate::request::backup::{BackupExportRequest, BackupImportRequest, BackupImportResponse};
use crate::response::Resp;
use crate::response::Response;
use crate::service;
use crate::service::backup::BackupEnvelope;
use application_database::account::access_token::AccessToken;
use application_kernel::result::ErrorCode;

#[handler]
pub async fn export(request: &mut Request, depot: &mut Depot) -> Resp<BackupEnvelope> {
    let access_token = depot
        .get_typed::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<BackupExportRequest>().await?;
    let params = params.validate()?;

    Ok(Response::success(
        service::backup::export(access_token, &params.kind, params.password).await?,
    ))
}

#[handler]
pub async fn import(request: &mut Request, depot: &mut Depot) -> Resp<BackupImportResponse> {
    let access_token = depot
        .get_typed::<AccessToken>()
        .map_err(|_| ErrorCode::AuthorizationAccessTokenInvalid)?;

    let params = request.parse_json::<BackupImportRequest>().await?;
    let params = params.validate()?;

    let imported =
        service::backup::import(access_token, &params.kind, params.password, params.backup).await?;

    Ok(Response::success(BackupImportResponse { imported }))
}
