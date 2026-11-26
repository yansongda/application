// 首页刷新的「这一次调用该干什么」决策（纯逻辑，无 ArkUI / 网络依赖，可在 `entry/src/test` 单测）。
//
// 背景：`Index` 里原来用「`SingleFlight.pending` + 一个手写布尔位 `inflightSilent`」表达三种意图，
// 注释写清了每个分支的由来（共享 / 补一次 / 新起），但这段恰好是「静默刷新、下拉刷新、重试按钮」
// 三条入口叠加时最容易出错的地方，却是全仓唯一没有用例保护的编排逻辑。
//
// 三个结论的语义：
// - `START`：当前没有在飞任务，直接开跑；`silent` 由调用方记录进本对象，供后到者判断；
// - `SHARE`：已有在飞任务且「后来者不需要交互式反馈」或「在飞的本来就是交互式」→ 共享同一个 Promise
//   （调用方会真正等它结束，而不是静默丢弃）；
// - `ENQUEUE`：在飞的是静默刷新，而本次需要交互式反馈（下拉刷新 / 重试按钮）→ 等它落地后**再补一次**
//   带 loading 的刷新，否则用户点了「重试」却看不到任何反馈（静默分支失败不弹框）。
//
// `plan()` 是同步的：`SingleFlight.enqueue` 会同步占位，因此「旧任务结束 → 新任务登记」之间没有并发缝隙。
export enum RefreshPlan {
  START = 0,
  SHARE = 1,
  ENQUEUE = 2,
}

export class RefreshPlanner {
  // 本次在飞任务是静默还是交互式（只对 START 有意义；ENQUEUE 会把它改回「非静默」）
  private _inflightSilent: boolean = false;

  // busy = 当前是否有在飞任务；silent = 本次调用是否静默
  plan(busy: boolean, silent: boolean): RefreshPlan {
    if (!busy) {
      this._inflightSilent = silent;

      return RefreshPlan.START;
    }

    if (silent || !this._inflightSilent) {
      return RefreshPlan.SHARE;
    }

    // 交互式调用撞上在飞的静默刷新：标记「接下来这次是交互式」，后到者不再重复补发
    this._inflightSilent = false;

    return RefreshPlan.ENQUEUE;
  }
}
