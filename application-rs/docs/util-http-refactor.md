# application-util HTTP 层重构方案（ResponseEnvelope + 错误码细分）

> **时间**：2026-08-27
> **作者**：GLM-5.3 + yansongda
> **状态**：经过人工审核确认（2026-08-27 对话内批准）

## 1. 背景与问题

**现状**：`application-util` 是全 workspace 唯一持有 reqwest 的 crate，`http::request<T>` 提供统一出站请求（日志/指标/错误分类），微信/华为各模块手写自定义 `Deserialize` 处理上游响应封套。唯一调用链为 `v1::access_token -> service::access_token -> wechat::login / huawei::token + token_info`，错误全部以 `ErrorCode` 经 `?` 透传（已验证，读过源码）。

**困境**：

1. **业务错误被拍平**：微信 `errcode`/华为 `error` 非 0 时，provider 在自定义 `Deserialize` 里 `de::Error::custom(...)` 抛错，业务错误与「响应体真是乱码」在类型层无法区分，最终都落 `ThirdHttpResponseParse(9802)`；`ThirdHttpResponseResult(9803)` 成为死码。
2. **错误码粒度不足**：timeout/connect/其他传输错误统一 `ThirdHttpRequest(9800)`，仅 Prometheus label 区分；`ThirdHttpResponse(9801)` 也是死码。
3. **样板重复**：每个 provider 手写「Raw + 公开」两套结构体 + 一份 Value-buffering `Deserialize`，共 3 份约 60 行的同构代码。
4. **坏味道**：`huawei.rs` 用 `RequestBuilder::from_parts(Client::new(), ...)` 构建请求——`Client::new()` 每次调用白白分配一个含连接池的对象后被丢弃（实际执行仍走 `G_CLIENT`，属浪费与误导而非行为错误；已验证，读过源码）。
5. **超时硬编码**：`G_CLIENT` 的 connect/total timeout 硬编码 1s/3s，`G_CONFIG` 无 HTTP 配置段。

**目标**（约束，非手段）：**业务错误类型化且可判别**；**调用方（application-api / application-database）零改动**；**客户端零逻辑回归**（前端不特判 98xx，已验证）；**零新增依赖**；**单一 PR 可整体回滚**。

## 2. 整体方案

**核心思路**：以「provider 响应类型自声明封套判别规则」的 trait（`ResponseEnvelope`）替代散落的手写 `Deserialize`，`http::request` 中心化驱动「HTTP 状态码轴 + body 判别轴」两轴判别，产出类型化的 `ResponseVariant<S, E>`；同时把 9800 系列错误码补全为完整分类学并配置化超时。

```
 application-api (service/v1)            application-database
      │  ErrorCode 经 ? 透传                    │ From<LoginResponse> 等
      ▼                                         │（结构体形状不变，零改动）
 application-util::wechat / huawei ◄────────────┘
      │ http::get(url) / http::post(url).form(...)
      ▼
 application-util::http::request::<T: ResponseEnvelope>
      │ G_CLIENT 执行（超时读 G_CONFIG.http，缺省 1s/3s）
      │ 轴 1: HTTP 非 2xx ──────────► 直接走 Error 分支
      │ 轴 2: 2xx 时咨询 T::is_success(&Value)
      ▼
 HttpResponse<T, T::Error> { status, duration, inner: ResponseVariant }
      │ provider 侧 match：Success -> Ok(S)；Error -> warn 日志 + 9803
      ▼
 ErrorCode ∈ {9800,9801,9802,9803,9804,9805} + metrics event（result label 7 值）
```

**文件结构**：

| 文件 | 变更 |
|---|---|
| `application-kernel/src/result.rs` | **新增** `ThirdHttpTimeout=9804`、`ThirdHttpConnect=9805`（`message()` 穷尽 match 补分支） |
| `application-kernel/src/prometheus.rs` | **新增** `business_error` / `response_error` 两个 label 常量 |
| `application-kernel/src/config.rs` | **新增** `http: Http` 配置段（connect/total 超时） |
| `application-util/src/http.rs` | **重构**：`ResponseEnvelope` trait、`ResponseVariant`、`HttpResponse<S,E>`、`get()/post()`、`request`、错误分类 |
| `application-util/src/wechat.rs` | **重构**：删自定义 `Deserialize` + `RawLoginResponse`，impl `ResponseEnvelope`，`login()` match |
| `application-util/src/huawei.rs` | **重构**：同上 ×2；删 `Client::new()`，改用 `http::post()` |
| `config.toml.example` | **新增** `[http]` 段示例 |

## 3. 详细设计

### 3.1 kernel：错误码分类学与配置

**错误码映射（改造前后）**：

| 场景 | 现码 | 新码 | 变体 |
|---|---|---|---|
| 请求执行失败（非超时/连接） | 9800 | 9800（不变） | `ThirdHttpRequest` |
| 响应体接收失败（`text()` 出错） | 9800 | **9801（启用死码）** | `ThirdHttpResponse` |
| JSON / S / E 反序列化失败 | 9802 | 9802（不变） | `ThirdHttpResponseParse` |
| provider 业务错误（Error 变体） | 9802（被拍平） | **9803（启用死码）** | `ThirdHttpResponseResult` |
| 超时（执行或读 body） | 9800 | **9804（新增）** | `ThirdHttpTimeout` |
| 连接失败 | 9800 | **9805（新增）** | `ThirdHttpConnect` |

新增消息模板：`"第三方错误: 第三方 API 请求超时,请联系管理员"`、`"第三方错误: 第三方 API 连接失败,请联系管理员"`。`message()` 为无通配符穷尽 match（已验证），漏补分支会编译失败——安全网内建。

**配置**（`[http]` 段整体可选，缺省 = 现硬编码值 1s/3s，存量 config.toml 零迁移）：

```toml
[http]
connect-timeout-secs = 1
timeout-secs = 3
```

> 落盘修订说明：对话内批准稿示例为 `connect_timeout_secs`（snake_case）+ `Option` 字段；落盘时按仓库既有约定（`config.rs` 全部配置段采用 `#[serde(default, deny_unknown_fields, rename_all = "kebab-case")]` + `Default` impl，如 `[bin-api]`/`[short-url]`/`[access-token]`）对齐为 kebab-case 键名 + 非 Option 字段 + `Http::default()`。语义不变：段缺失取默认 1/3。

### 3.2 http.rs：封套判别核心

> **2026-08-28 修订**：`ResponseVariant` 已删除，判别结果直接以 `std::result::Result<T, T::Error>` 表示（成功载荷即 `Self`，无需新增关联类型）；`ResponseEnvelope` / `HttpResponse` 分别更名为 `Body` / `Response`（结果字段名 `body`）。下文代码与图表保留历史原貌。

```rust
/// provider 响应类型自声明的封套判别规则；is_success 仅在 HTTP 2xx 时被咨询
pub trait ResponseEnvelope: Debug + DeserializeOwned {
    type Error: Debug + DeserializeOwned;
    fn is_success(body: &Value) -> bool;
}

pub enum ResponseVariant<S, E> { Success(S), Error(E) }   // 普通枚举，无自定义 Deserialize

pub async fn request<T: ResponseEnvelope>(req: Request) -> Result<HttpResponse<T, T::Error>>
```

`request` 主流程（伪代码）：

```
resp  = G_CLIENT.execute(req)      // 失败: timeout->9804, connect->9805, else->9800
body  = resp.text()                // 失败: timeout->9804, else->9801
value = parse_json(body)           // 失败: 9802
inner = if status.is_success() && T::is_success(&value) { Success(from_value::<T>) }
        else { Error(from_value::<T::Error>) }              // 二次解析失败均->9802
emit_event(result = success | business_error)               // 按 inner 变体
```

对比两个来源的设计决策：

| 决策点 | message-util | 本方案 | 理由 |
|---|---|---|---|
| 判别位置 | `ResponseVariant` 自定义 `Deserialize` 内（硬编码 `code==0\|\|200`） | `request` 运行时经 trait 驱动 | 三个 provider 判别约定异构，trait 让判别规则与类型绑定、机制中心化 |
| 无 `code` 兜底 | 先试 S 再试 E 的盲试 | 无兜底，判别器直接给 bool | 消除「畸形 body 误判为 E」的隐患，确定性更强 |
| HTTP 状态码轴 | 不参与判别 | 非 2xx 直接走 Error 分支 | 对齐 oauth2 crate 权威模式；华为 OAuth（RFC 6749）非 200 + error body 场景更稳 |
| variant 访问器 | `is_success/into_success/into_error` | 不设，用 `match` | 调用方本就要在 Error 臂记 provider 字段日志，访问器无实际消费方 |

`get(url) -> RequestBuilder` / `post(url) -> RequestBuilder` 直接暴露 `G_CLIENT`（per-request `.timeout()` 因此天然可用，不专门设计）；`G_CLIENT` 初始化时读 `G_CONFIG.http`。

**不采用 `RequestBuilder::query`**（审查修正，B1）：reqwest 0.13 的 `query` 方法被独立 `query` feature 门控（已验证，读 reqwest 0.13.4 源码 `async_impl/request.rs` 的 `#[cfg(feature = "query")]`），当前依赖仅启用 `form`。启用 `query` 不会新增任何包（两 feature 依赖构成完全相同：`dep:serde` + `dep:serde_urlencoded`，已验证），但需要改 Cargo.toml，违反「所有 Cargo.toml 零改动」约束，故微信 query 参数保留 `Url::parse_with_params` 预构造后传入 `http::get(url.as_str())`。

### 3.3 provider 适配与判别契约

**判别器约定**（契约标注）：

| provider 类型 | `is_success` 逻辑 | 契约来源 |
|---|---|---|
| `wechat::LoginResponse` | `errcode` 缺失或 `== 0` | **已验证**（读过源码与现有测试逻辑）；真实 API 行为**推断（未实测）** |
| `huawei::TokenResponse` | `error`（数值）缺失或 `== 0` | 同上 |
| `huawei::TokenInfoResponse` | `error`（字符串）缺失或为空 | 同上 |

无法安排真实环境 spike（需有效 code/token 凭证）；缓解措施见风险表（E 类型宽松化）。

provider 侧新形态（以 `login()` 为例，伪代码）：

```
url  = Url::parse_with_params(URL, &[(appid, ...), ...])     // 解析失败->9800
req  = http::get(url.as_str()).build()                        // 构建失败->9800
resp = http::request::<LoginResponse>(req).await?
match resp.inner:
    Success(s) -> Ok(s)
    Error(e)   -> warn!(errcode, errmsg, "微信业务错误"); Err(ThirdHttpResponseResult)  // 9803
```

配套清理：删除 `RawLoginResponse` / `RawTokenResponse` / `RawTokenInfoResponse` 与三份自定义 `Deserialize`；E 类型**宽松化**——华为 `error_description` 按 RFC 6749 属可选字段，改为 `Option<String>`（微信 `errmsg` 维持必填）；`TokenResponseError` 等摘除 `#[allow(dead_code)]`（正式投入使用）。

### 3.4 测试策略

现有 7 个 provider 反序列化测试**重写**为 13 个判别器表驱动测试（3 provider × 成功/业务错误/判别字段缺失 + E 宽松化场景；wechat 3->6、huawei 4->7）；kernel 侧 result 补 9804/9805 的 code 与 message 断言（现有 `test_error_code_ranges` 为精确值元组断言，扩展两个元组即可）、config 补 `[http]` 段覆盖默认/缺省/拒绝未知字段三类测试（kernel 合计 +5）；`normalize_url` 测试保留。util 总测试 8 -> 14，workspace 净增 11。

### 3.5 兼容性

**编译影响面**（已验证，全量 grep）：仅 `application-util` 内部 3 处 `http::request` 调用点；`application-database` 的 `From<LoginResponse>`、`application-api` 全链路**零改动**（公开结构体字段形状不变，错误仍为 `ErrorCode` 透传）。

**客户端可见变化**（前端不特判 98xx，已验证微信 `error.ts`/`http.ts` 与华为 `AccessToken.ets`）：

| 场景 | code 前->后 | message 前->后 |
|---|---|---|
| 业务错误 | 9802->9803 | 响应解析出错->业务结果出错 |
| 超时 | 9800->9804 | 请求出错->请求超时 |
| 连接失败 | 9800->9805 | 请求出错->连接失败 |
| body 接收失败 | 9800->9801 | 请求出错->响应出错 |

provider 细节（errcode/errmsg 值）从客户端 message 移入服务端日志——不向上游泄露内部细节，与 kernel 错误模型一致。

## 4. 推进策略

```
阶段 1  kernel 变更（错误码/label 常量/配置段）
        验证点: cargo test -p application-kernel 全绿；此时新变体无人使用，行为零变化
阶段 2  util 重构（http.rs 核心 + wechat/huawei 适配 + 测试重写）
        验证点: cargo check/clippy/fmt/test --all-features 全绿
阶段 3  部署观察 1~2 天（/metrics 与日志，见第 6 节预期）
```

**回滚**：整 PR 单次 revert；无 DB/schema 变更。**配置兼容性是单向的**（审查修正，M1）：新代码兼容无 `[http]` 段的旧配置；但旧代码遇到带 `[http]` 段的配置会因 `deny_unknown_fields` 反序列化失败、`G_CONFIG` 启动 panic（已验证，读 config.rs）。因此回滚 SOP：revert 代码的同时**删除 config.toml 的 `[http]` 段与 `APP__HTTP__*` 环境变量**。

## 5. 风险与对策

| 风险 | 严重度 | 对策 |
|---|---|---|
| 客户端可见 code/message 变化 | 低 | 前端已核实不特判 98xx；发布说明附 3.5 节映射表 |
| E 反序列化失败使业务错误落到 9802（如华为缺 `error_description`） | 中 | E 字段宽松化（Option）+ 畸形 body 表驱动测试 |
| 华为非 2xx + 非 JSON body（代理 502 页面）归 9802 | 低 | 与现状一致；日志已含原始 body 可排查 |
| 上游非 2xx 但 body 呈成功形状（如网关错误页夹带 `errcode: 0`） | 低 | 行为变化：现状会解析成功并返回，新方案非 2xx 强制走 Error 分支 -> E 解析失败 -> 9802。概率极低，接受此变化（更符合 HTTP 语义） |
| 判别契约与真实 API 不符（未经实测） | 中 | 判别逻辑仅移动未发明（与现有 `Deserialize` 逐字段对齐）；观察期监控 `business_error`/`parse_error` 占比 |
| `[http]` 配置类型错误导致启动失败 | 低 | fail-fast 符合仓库惯例；段可选、缺省零变化 |
| `message()` 漏补新分支 | 低 | 无通配符穷尽 match，编译期强制（已验证） |

## 6. 监控与可观测性

事件结构不变，`result` 取值从 5 个扩到 7 个（`MetricsLayer` 按 label value 动态打点，零注册改动，已验证）：

```json
{"event":"outbound_http_request","url":"https://api.weixin.qq.com/sns/jscode2session","result":"business_error","duration_seconds":0.312}
```

| 指标 | 预期变化 | 观察 |
|---|---|---|
| `outbound_http_requests_total{result="parse_error"}` | 下降（业务错误迁出） | 环比对照 |
| `outbound_http_requests_total{result="business_error"}` | 新序列 | 若占比异常高，提示判别契约与真实 API 不符 |
| `outbound_http_requests_total{result="response_error"}` | 新序列（预期稀少） | 持续非零提示上游/网络异常 |
| 日志错误码 9804/9805 | 与 `timeout`/`connect_error` label 一一对应 | 抽查对齐 |

复用现有 `/metrics` 路由与 `MetricsLayer` 通道，不新增告警规则（现有体系未配置告警，维持现状）。

## 附录 A：明确排除项（Must NOT）

- 不改 `application-api` / `application-database` 任何代码
- 不新增依赖（`serde_path_to_error` 等调研中出现的可选项明确排除）
- 不做 URL 配置化（维持常量，如需另行立项）
- 不改连接池参数的可配置性（仅超时两项）——**2026-08-28 修订**：连接池 idle/max-idle/keepalive 三参数已按后续决策配置化，纳入 `[http]` 段

## 附录 B：调研来源

- 代码库现状调研（2026-08-27，全量 grep + 逐文件阅读）：调用链、错误模型、指标机制、配置结构、前端错误码消费方式均已验证。
- 外部模式调研（serde 文档、oauth2 crate、open_wechat、reqwest 文档）：trait + associated types 的判别器抽象为选型结论，来源清单见调研记录。
