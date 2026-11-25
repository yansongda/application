/**
 * 单字段编辑页（`totp/edit/issuer`、`totp/edit/username`）共用的提交流程：
 * 校验非空 → 「更新中」loading → 接口 → 更新本地缓存 → 成功 Toast → 延时返回；
 * 失败统一走「更新失败：<message>」顶部横幅（不再额外弹一个同义的 Toast）。
 *
 * 之所以不抽「页面工厂」：页面方法的 `this` 由 `Page()` 的 `ThisType` 上下文提供，
 * 搬进工厂函数后会丢失，只能靠 `as` 断言去补；为省 20 行引入断言不划算，
 * 因此这里只共享流程，各页仍保留自己的 data / 表单绑定 / 文案。
 */
import error from "./error";
import { withLoading } from "./loading";
import { notify, toast } from "./notify";

type MessageHost = Parameters<typeof notify.error>[0];

export interface EditFieldInput {
  /** 页面实例：仅用于把顶部横幅挂到当前页 */
  host: MessageHost;
  /** 条目 id */
  id: string;
  /** 已 trim 的新值 */
  value: string;
  /** 空值提示文案 */
  emptyMessage: string;
  /** 真正的保存请求 */
  submit: (id: string, value: string) => Promise<unknown>;
  /** 成功后写本地缓存（写哪个字段由页面决定） */
  onSaved: (value: string) => void;
}

export const submitEditField = async (input: EditFieldInput): Promise<void> => {
  if (input.value.length === 0) {
    // 空值不提交：提示后返回，不发请求
    toast.error(input.emptyMessage, 1500);

    return;
  }

  try {
    await withLoading("更新中...", () => input.submit(input.id, input.value));

    input.onSaved(input.value);

    toast.success("修改成功", 1500);

    setTimeout(() => wx.navigateBack(), 1500);
  } catch (e: unknown) {
    notify.error(input.host, `更新失败：${error.getErrorMessage(e)}`);
  }
};
