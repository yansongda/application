import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPagesName, LogDomain } from '../App';
import { AppStorageV2, UIContext } from '@kit.ArkUI';
import { PromptAction as OhosPromptAction } from '@ohos.arkui.UIContext';
import promptAction from '@ohos.promptAction';

class PromptAction {
  private static _action: OhosPromptAction | undefined;

  protected static get action(): OhosPromptAction {
    if ('undefined' === typeof PromptAction._action) {
      PromptAction._action = AppStorageV2.connect(UIContext)!.getPromptAction();
    }

    return PromptAction._action;
  }

  private static _pages: NavPathStack | undefined;

  protected static get pages(): NavPathStack {
    if ('undefined' === typeof PromptAction._pages) {
      PromptAction._pages = AppStorageV2.connect(NavPathStack)!;
    }

    return PromptAction._pages;
  }
}

export class Dialog extends PromptAction {
  static async open(builder: CustomBuilder): Promise<number | undefined> {
    try {
      return await PromptAction.action.openCustomDialog({ builder, autoCancel: false });
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/dialog', '调用 `openCustomDialog` 失败，调用链路: %{public}s',
        JSON.stringify(e));
    }

    return undefined;
  }

  static close(dialogId: number | undefined) {
    if ('undefined' === typeof dialogId) {
      return;
    }

    try {
      PromptAction.action.closeCustomDialog(dialogId);
    } catch (e) {
      hilog.error(LogDomain.UTILS, 'utils/dialog', '调用 `closeCustomDialog` 失败，调用链路: %{public}s',
        JSON.stringify(e));
    }
  }

  static async execute<T>(openBuilder: CustomBuilder, callback: () => Promise<T>,
    retryBuilder?: CustomBuilder): Promise<T> {
    const dialogId = await Dialog.open(openBuilder);

    let error: undefined | Error = undefined;

    try {
      const result = await callback();

      Dialog.close(dialogId);

      return result;
    } catch (e) {
      error = e;
    }

    Dialog.close(dialogId);

    if (typeof retryBuilder !== 'undefined') {
      Dialog.open(retryBuilder);
    }

    return Promise.reject(error);
  }
}

export class Toast extends PromptAction {
  static show(options: promptAction.ShowToastOptions): void {
    if (AppPagesName.LOGIN.toString() === (PromptAction.pages.getAllPathName()[0] ?? 'undefined')) {
      return;
    }

    try {
      PromptAction.action.showToast(options);
    } catch (error) {
      hilog.warn(LogDomain.UTILS, 'utils/toast', '调用 `showToast` 失败: %{public}s', JSON.stringify(error));
    }
  }

  static async execute<T>(
    callback: () => Promise<T>,
    openBuilder?: CustomBuilder,
    successMessage?: Resource | string | undefined,
    failedMessage?: Resource | string | undefined
  ): Promise<T> {
    let dialogId: number | undefined;

    if (openBuilder) {
      dialogId = await Dialog.open(openBuilder);
    }

    try {
      const result = await callback();

      Dialog.close(dialogId);

      if (successMessage) {
        Toast.show({
          message: successMessage,
          duration: 3000,
        });
      }

      return result;
    } catch (e) {
      Dialog.close(dialogId);

      Toast.show({
        message: failedMessage ?? e.message,
        duration: 3000,
      });

      return Promise.reject(e);
    }
  }
}
