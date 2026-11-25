/**
 * 页面级轻提示统一入口：收敛各页面逐字重复的 tdesign 配置（offset / duration / direction）。
 *
 * - `notify.*`：顶部横幅（Message），需要页面声明 `<t-message id="t-message" />`
 * - `toast.*`：居中气泡（Toast），需要页面声明 `<t-toast id="t-toast" />`
 *
 * 不变量：只传面向用户的文案。密钥、验证码、备份口令一律不得经由本模块或日志输出。
 * 组件内需要绑定自身 context 的 Toast（如锁屏遮罩）仍直接调用 tdesign，不走这里。
 */
import Message from "tdesign-miniprogram/message/index";
import Toast from "tdesign-miniprogram/toast/index";

type MessageOptions = Parameters<typeof Message.error>[0];
type MessageHost = MessageOptions["context"];

// 顶部横幅统一间距（与既有各页手写值保持一致，改动需真机视觉确认）
const MESSAGE_OFFSET: MessageOptions["offset"] = [20, 32];

const notify = {
  error(host: MessageHost, content: string): void {
    Message.error({
      content,
      duration: 5000,
      offset: MESSAGE_OFFSET,
      context: host,
    });
  },
  warning(host: MessageHost, content: string): void {
    Message.warning({
      content,
      duration: 3000,
      offset: MESSAGE_OFFSET,
      context: host,
    });
  },
  info(host: MessageHost, content: string): void {
    Message.info({
      content,
      duration: 5000,
      offset: MESSAGE_OFFSET,
      context: host,
    });
  },
};

const toast = {
  success(message: string, duration = 1500): void {
    Toast({
      message,
      theme: "success",
      duration,
      direction: "column",
      preventScrollThrough: true,
    });
  },
  error(message: string, duration = 1500): void {
    Toast({ message, theme: "error", duration, direction: "column" });
  },
};

export { notify, toast };
