use crate::response::AppErr;
use application_database::account::access_token;
use application_kernel::events::HTTP_REQUEST;
use application_kernel::logger::truncate_for_log;
use application_kernel::result::ErrorCode;
use bytes::Bytes;
use futures_util::StreamExt;
use salvo::http::header::AUTHORIZATION;
use salvo::http::{Mime, StatusCode, mime};
use salvo::{Depot, FlowCtrl, Request, Response, handler};
use std::time::Instant;
use tracing::Instrument;
use ulid::Ulid;

#[handler]
pub async fn tracing_id(
    request: &mut Request,
    depot: &mut Depot,
    response: &mut Response,
    ctrl: &mut FlowCtrl,
) {
    let id = Ulid::generate().to_string();
    request
        .headers_mut()
        .insert("x-request-id", id.parse().unwrap());
    response
        .headers_mut()
        .insert("x-request-id", id.parse().unwrap());

    let span = tracing::info_span!("http.request", request_id = %id);
    application_kernel::logger::TracingId::attach(&span, &id);

    ctrl.call_next(request, depot, response)
        .instrument(span)
        .await;
}

#[handler]
pub async fn authorization(
    request: &mut Request,
    depot: &mut Depot,
    response: &mut Response,
    ctrl: &mut FlowCtrl,
) {
    macro_rules! abort {
        ($error:expr) => {{
            response.render(AppErr($error));
            ctrl.skip_rest();
            return;
        }};
    }

    let auth = match request.headers().get(AUTHORIZATION) {
        Some(h) => match h.to_str() {
            Ok(a) => a,
            Err(_) => abort!(ErrorCode::AuthorizationInvalidFormat),
        },
        None => abort!(ErrorCode::AuthorizationHeaderMissing),
    };

    let token = auth.strip_prefix("Bearer ").unwrap_or(auth);
    let access_token = match access_token::fetch(token).await {
        Ok(t) if !t.is_expired() => t,
        Ok(_) => abort!(ErrorCode::AuthorizationAccessTokenExpired),
        Err(_) => abort!(ErrorCode::AuthorizationAccessTokenInvalid),
    };

    depot.insert_typed(access_token);

    ctrl.call_next(request, depot, response).await;
}

#[handler]
pub async fn request_logger(
    request: &mut Request,
    depot: &mut Depot,
    response: &mut Response,
    ctrl: &mut FlowCtrl,
) {
    let path = request.uri().path().to_string();

    if path == "/health" || path == "/metrics" {
        ctrl.call_next(request, depot, response).await;
        return;
    }

    let start = Instant::now();

    let req_body = match request.content_type() {
        Some(ct) if is_loggable_mime(&ct) => match request.payload().await {
            Ok(bytes) => truncate_for_log(&bytes[..]),
            Err(_) => String::from("<payload read error>"),
        },
        Some(_) => String::from("非 JSON 或表单请求"),
        None => String::from("未知数据源请求"),
    };

    tracing::info!(
        method = %request.method(),
        uri = %request.uri(),
        headers = ?request.headers(),
        body = %req_body,
        "--> 接收到请求"
    );

    ctrl.call_next(request, depot, response).await;

    let elapsed_secs = start.elapsed().as_secs_f64();

    let res_body = match response.content_type() {
        Some(ct) if is_loggable_mime(&ct) => read_body_for_log(response).await,
        _ => String::new(),
    };

    tracing::info!(
        event = HTTP_REQUEST,
        method = request.method().as_str(),
        path = path.as_str(),
        status = response.status_code.unwrap_or_default().as_str(),
        duration_seconds = elapsed_secs,
        body = %res_body,
        "<-- 请求处理完成"
    );
}

#[handler]
pub fn catcher(_req: &Request, _depot: &Depot, res: &mut Response, ctrl: &mut FlowCtrl) {
    let error_code = match res.status_code {
        Some(StatusCode::NOT_FOUND) => ErrorCode::StatusNotFound,
        Some(StatusCode::METHOD_NOT_ALLOWED) => ErrorCode::StatusMethodNotAllowed,
        Some(StatusCode::INTERNAL_SERVER_ERROR) => ErrorCode::UnknownError,
        _ => return,
    };

    res.status_code(StatusCode::OK);
    res.render(crate::response::Response::<String>::error(error_code));

    ctrl.skip_rest();
}

fn is_loggable_mime(ct: &Mime) -> bool {
    ct.subtype() == mime::JSON || ct.subtype() == mime::WWW_FORM_URLENCODED
}

async fn read_body_for_log(res: &mut Response) -> String {
    let mut body = res.take_body();
    let mut bytes = Vec::new();

    while let Some(Ok(chunk)) = body.next().await {
        if let Ok(data) = chunk.into_data() {
            bytes.extend_from_slice(&data);
        }
    }

    let res_bytes = Bytes::from(bytes);
    res.body(res_bytes.clone());

    truncate_for_log(&res_bytes)
}
