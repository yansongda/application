// 认证状态（叶子模块）：只放枚举，不 import 任何业务模块。
//
// 原先定义在 models/Auth.ets，而 Nav/Http/FormIntent 只需要这个枚举，
// 却会因此把「模型 → api → Http」整条依赖链带进来，形成循环。集中到这里后依赖方向单向。
export enum State {
  EMPTY_AUTHORIZATION = 0,

  NEED_REFRESH = 1,

  REFRESH_TOKEN_EXPIRED = 2,

  NORMAL = 3,
}
