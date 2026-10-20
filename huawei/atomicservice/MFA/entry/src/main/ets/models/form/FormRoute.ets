// 卡片意图路由：与服务卡片 postCardAction 的 params.mfa_route 约定一致。
// 本文件不依赖任何 Kit，卡片侧（系统进程）可安全引用；
// FormIntent 负责 want 解析，本文件只承载路由常量与编解码。
export const FORM_ROUTE_PARAM: string = 'mfa_route';

export enum FormRoute {
  // 直达扫码添加
  SCAN = 'scan',
  // 直达手动输入添加页
  INPUT = 'input',
}

// 解析原始字符串：未知值一律视为无快捷意图（普通点卡）
export function parseFormRoute(value: string | undefined): FormRoute | undefined {
  if (FormRoute.SCAN === value) {
    return FormRoute.SCAN;
  }

  if (FormRoute.INPUT === value) {
    return FormRoute.INPUT;
  }

  return undefined;
}

// 构造 postCardAction 的 params，避免卡片侧散落参数名与路由字面量
export function formRouteParams(route: FormRoute): Record<string, string> {
  const params: Record<string, string> = {};

  params[FORM_ROUTE_PARAM] = route;

  return params;
}
