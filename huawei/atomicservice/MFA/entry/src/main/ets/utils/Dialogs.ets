import { AdvancedDialogV2Button, AlertDialogV2, LoadingDialogV2 } from '@kit.ArkUI';

// 统一弹窗集合：多个页面形态一致的 loading / 失败 / 可重试对话框集中在此，避免各页面重复实现

@Builder
export function loadingDialog(content?: Resource) {
  LoadingDialogV2({
    content: content ?? $r('app.string.handling'),
  })
}

// 仅确认按钮的失败提示
@Builder
export function failedDialog(title: ResourceStr, content: ResourceStr) {
  AlertDialogV2({
    primaryTitle: title,
    content,
    primaryButton: new AdvancedDialogV2Button({
      content: $r('app.string.ok'),
      role: ButtonRole.ERROR,
    }),
  })
}

// 取消 + 重试
@Builder
export function retryDialog(title: ResourceStr, content: ResourceStr, action: () => void) {
  AlertDialogV2({
    primaryTitle: title,
    content,
    primaryButton: new AdvancedDialogV2Button({
      content: $r('app.string.cancel'),
    }),
    secondaryButton: new AdvancedDialogV2Button({
      content: $r('app.string.retry'),
      role: ButtonRole.ERROR,
      action
    }),
  })
}
