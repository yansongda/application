// 使用帮助页（占位）：本轮只渲染标题，内容由 Task 7 填充。
@Builder
export function builder() {
  Help()
}

@ComponentV2
struct Help {
  build() {
    NavDestination() {
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .title($r('app.string.user_help_page_title'))
  }
}
