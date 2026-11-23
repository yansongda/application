// 请求/流程单飞（纯逻辑，无 ArkUI 依赖，可在 `entry/src/test` 单测）。
//
// 仓库里原先有三处手写单飞，语义各不相同：
// - `pages/Login.ets`：布尔锁，第二个调用方**静默丢弃**（用户点重试像没反应）；
// - `pages/index/Index.ets`：Promise 单飞 + 额外布尔位，后到者等待（这里等待才对，否则下拉刷新「空转」）；
// - `models/security/Sync.ets`：布尔位，且在「补发」时先清标志再重入（微任务缝隙里第三方会并发）。
//
// 两种原语就够了：
// - `run(task)`：已有在飞任务就**共享**同一个 Promise（不排队、不重复执行）；
// - `enqueue(task)`：等当前任务落地后**再执行一次**，并同步占位（给「期间又发生了变化，需要补一次」用）；
// - `busy`：给「重复触发应当直接丢弃」的调用方用（如登录重入锁）。
//
// 用 Promise 而不是布尔位：布尔位要靠 `try/finally` 或每个分支手动复位，
// 漏一处就永久卡住；Promise 的 then/catch 一定成对执行。
export class SingleFlight<T> {
  private _pending: Promise<T> | undefined = undefined;

  get busy(): boolean {
    return 'undefined' !== typeof this._pending;
  }

  // 当前在飞任务（没有则 undefined）：调用方据此决定「等它」还是「补一次」
  get pending(): Promise<T> | undefined {
    return this._pending;
  }

  run(task: () => Promise<T>): Promise<T> {
    const pending: Promise<T> | undefined = this._pending;

    if ('undefined' !== typeof pending) {
      return pending;
    }

    return this.start(task);
  }

  // 等当前在飞任务落地后再执行一次 task，并把新任务**同步**登记为「在飞」。
  // 同步占位很关键：否则「旧任务结束」与「新任务登记」之间的微任务缝隙里，
  // 第三个调用方会以为没人干活，另起一次并发请求。
  enqueue(task: () => Promise<T>): Promise<T> {
    const pending: Promise<T> | undefined = this._pending;

    if ('undefined' === typeof pending) {
      return this.start(task);
    }

    const again = (): Promise<T> => this.start(task);
    const chained: Promise<T> = pending.then(again, again);

    this._pending = chained;

    return chained;
  }

  private start(task: () => Promise<T>): Promise<T> {
    const running: Promise<T> = task();

    this._pending = running;

    const clear = (): void => {
      // 只清理自己：清场/排队可能已经让 `_pending` 指向新一轮任务
      if (this._pending === running) {
        this._pending = undefined;
      }
    };

    running.then(clear, clear);

    return running;
  }
}
