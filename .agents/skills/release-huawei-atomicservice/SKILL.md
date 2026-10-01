---
name: release-huawei-atomicservice
description: 在发布 huawei/atomicservice/MFA 下的华为元服务（atomic service）前端时使用 —— 提升 AppScope/app.json5 的 versionCode/versionName、新增 CHANGELOG.md 段落、创建 release PR、打 huawei-atomicservice-mfa/vX.Y.Z tag，或准备用于 AGC（AppGallery Connect）上架的签名 .app
---

# 发布华为元服务（Huawei Atomic Service MFA）

## 概述

华为元服务前端位于 `huawei/atomicservice/MFA/`，使用 ArkTS/ETS 构建。

**与微信小程序的关键差异：** 版本号不在 `package.json` / `oh-package.json5` 里，而是在 `AppScope/app.json5` 中的 `versionCode` + `versionName`。另外该项目**没有 CI**：打包和上架都靠手动操作 DevEco Studio + AGC。

**核心原则：** 提升版本号 & 更新 CHANGELOG → **创建 PR** → **用户手动合并** → 打 tag & 推送 → **手动** DevEco Studio 构建 + AGC 上传。

**⚠️ 必须创建 PR。绝不直推 main。**
**⚠️ 绝不能自动合并 PR。必须由用户审核并手动合并。**
**⚠️ 绝不能尝试自动化 AGC 上传**（需要交互式登录华为开发者账号）。

## 适用场景

- 发布华为元服务（MFA）新版本
- 提升 `huawei/atomicservice/MFA/AppScope/app.json5` 中的 `versionCode` / `versionName`
- 为华为前端新增 CHANGELOG 段落
- 创建或推送 tag `huawei-atomicservice-mfa/vX.Y.Z`
- 准备用于 AGC 上架的签名 `.app` 包

不适用：微信小程序（**必须**使用 frontend-miniprogram-release）、Rust 后端（**必须**使用 release-application-rs）。

## 关键事实（已在本仓库核实）

| 项目 | 值 |
|------|-------|
| 项目根目录 | `huawei/atomicservice/MFA/` |
| 版本号来源 | `AppScope/app.json5` → `"versionCode": <int>`、`"versionName": "X.Y.Z"` |
| versionCode 规则 | `MAJOR*10000 + MINOR*100 + PATCH`（v1.0.0 = `10000`，v1.3.1 = `10301`） |
| CHANGELOG | `huawei/atomicservice/MFA/CHANGELOG.md`（Keep a Changelog） |
| Tag 格式 | `huawei-atomicservice-mfa/vX.Y.Z`（轻量 tag） |
| Bundle | `com.atomicservice.6917576589568238756`，`bundleType: atomicService` |
| 签名包 | `huawei/atomicservice/MFA/build/outputs/default/MFA-default-signed.app`（构建产物，绝不提交） |
| 构建与上传 | DevEco Studio GUI + AGC 网页控制台 —— 仓库里没有提交 `hvigorw` CLI wrapper |
| CI | huawei 没有 CI。推送 tag 仍会触发 `.github/workflows/build-image.yml`（它监听 `**`），但每个 job 都会被其 `application-api` 守卫跳过 —— 全部 skipped 的运行是**预期行为**，不是失败。 |

## 操作流程

### 第 1 步：检查当前状态

```bash
cd huawei/atomicservice/MFA

git status --short
git branch --show-current
git tag -l 'huawei-atomicservice-mfa/*' | sort -V | tail -5
grep -E 'versionCode|versionName' AppScope/app.json5
```

**若有未提交改动：** 停下来，先弄清*具体*是什么改动：
- `huawei/atomicservice/MFA/` 内属于本次发布的改动（待提升的版本号、CHANGELOG 条目）→ 保留，并带到 release 分支中一起提交
- 其他任何改动（无关的在建工作）→ 先提交或 stash，并确保不进入 release PR

绝不要为了让工作区干净而丢弃或 stash-drop 与发布相关的修改。

**隔离改动范围（关键）。** 当前分支往往是夹杂无关工作的功能分支：

```bash
# 错误：包含了分支上的所有改动
git diff main..HEAD --stat

# 正确：只检查目标目录中的改动
git diff main..HEAD -- huawei/
```

`app.json5` 中的 `versionName` 有时会随功能开发一起提升，因此可能已经**领先于最新 tag**（例如 2026-09 状态：HEAD 为 `1.4.0` / `10400`，而最新 tag 是 `v1.3.1`）。这种情况下待发布的版本就是 `1.4.0`，release PR 只需要补 CHANGELOG 段落。

### 第 2 步：确定版本号

**commit message 只是线索，diff 才是事实。**

```bash
# 第 1 步：列出上个 tag 之后的提交（仅供参考）
git log <PREV_TAG>..HEAD --oneline -- huawei/

# 第 2 步：查看每个提交的实际改动（这才是关键依据）
git show --stat <commit> -- huawei/

# 第 3 步：审查整体 diff
git diff <PREV_TAG>..HEAD -- huawei/
```

一个 `chore:` 提交可能新增整个页面（MINOR），一个 `feat:` 提交可能只是改了字符串资源（PATCH）。根据**行为影响**套用 [SemVer](https://semver.org/lang/zh-CN/)：

| 改动内容 | 版本提升 | 示例 |
|--------------|-------------|---------|
| 新增面向用户的页面 / 功能 / API 调用 | **MINOR** | `1.3.1` → `1.4.0` |
| 有行为变化的缺陷修复 | **PATCH** | `1.3.0` → `1.3.1` |
| 纯重构 / 注释或资源重命名 | **不提升** 或与其他改动合并发布 | 若无用户可见变化，可跳过发版 |
| 破坏性变更（移除页面、改变鉴权流程） | **MAJOR** | `1.3.1` → `2.0.0` |

然后根据目标版本计算 `versionCode` —— 它**不是**独立计数器：

```
versionCode = MAJOR * 10000 + MINOR * 100 + PATCH
```

- `1.4.0` → `10400`，`1.3.1` → `10301`，`2.0.0` → `20000`
- **绝不复用 versionCode。** AGC 会拒绝 versionCode 不大于已发布版本的包，所以即使只提升 PATCH 也必须使用新号。

### 第 3 步：更新 `app.json5` & `CHANGELOG.md`

**`AppScope/app.json5`** —— 只改这两行：

```json5
{
  "app": {
    "bundleName": "com.atomicservice.6917576589568238756",
    "bundleType": "atomicService",
    "vendor": "yansongda",
    "versionCode": 10400,        // MAJOR*10000 + MINOR*100 + PATCH
    "versionName": "1.4.0",      // 必须等于 tag 版本号
    "icon": "$media:icon",
    "label": "$string:app_name",
    "description": "$string:app_description"
  }
}
```

绝不要动 `bundleName`（AGC 靠它把包与应用匹配），也不要动 `build-profile.json5` 中的签名配置（本机绝对路径 + DevEco 加密口令；改动会导致签名失效）。

**`CHANGELOG.md`** —— [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式，与 `wechat/miniprogram/yansongda`、`wechat/miniprogram/totp` 一致：

```markdown
# Changelog

本文件遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.4.0] - YYYY-MM-DD

### Added

- TOTP 验证码改为端内离线计算，无需每次请求后端 (#PR)

### Changed

- 优化「我的」页面编辑交互 (#PR)

### Fixed

- 修复头像整体替换导致 UI 不刷新 (#PR)
```

**格式检查清单：**
- [ ] 版本标题：`## [X.Y.Z] - YYYY-MM-DD`（不是 `## vX.Y.Z`，日期不可省略）
- [ ] 段落标题使用英文并首字母大写，每种变更类型一个：`### Added` / `### Changed` / `### Deprecated` / `### Removed` / `### Fixed` / `### Security`
- [ ] 中文单行条目，描述**用户可见行为**；有 PR 编号时追加 `(#PR)`
- [ ] 新版本段落加在文件**最上方**
- [ ] 保留文件顶部的 `# Changelog` 标题 + 规范说明行
- [ ] 日期必须是实际发布日期 —— 用 `date +%F` 读取；绝不臆造或照抄
- [ ] 文件中所有标题都使用 `## [X.Y.Z] - YYYY-MM-DD` —— 绝不新增 `## vX.Y.Z` 标题；若仍存在旧格式标题，在同一次提交中一并转换

**获取上次发布以来的提交：**
```bash
git log <PREV_TAG>..HEAD --pretty=format:"- %s" -- huawei/
```

若依赖有变化，还需 stage `oh-package.json5` + `oh-package-lock.json5`（锁文件必须始终提交）。

### 第 4 步：创建 Release PR

```bash
git checkout main && git pull origin main
git checkout -b release/huawei-atomicservice-vX.Y.Z
git add huawei/atomicservice/MFA/AppScope/app.json5 huawei/atomicservice/MFA/CHANGELOG.md
git commit -m "release(huawei): vX.Y.Z"
git push -u origin release/huawei-atomicservice-vX.Y.Z
gh pr create --title "release(huawei): vX.Y.Z" --body "Release huawei atomic service vX.Y.Z"
```

- 若版本号已随功能开发提升过，则只 stage `CHANGELOG.md` —— 并在 PR 描述中说明。
- 由于 huawei 没有 CI lint/build，打开 PR 前先在 DevEco Studio 中打开项目确认能编译（且 code-linter 无告警）。
- **等待用户手动审核并合并。绝不自动合并。**
- 绝不 `git push` 到 main；绝不 force-push。

### 第 5 步：打 Tag & 推送（PR 合并后）

```bash
git checkout main && git pull origin main

git tag huawei-atomicservice-mfa/vX.Y.Z
git push origin huawei-atomicservice-mfa/vX.Y.Z
```

- 轻量 tag；`huawei-atomicservice-mfa/` 前缀是硬性要求，必须与现有 tag 完全一致。
- 务必先拉取最新 main，确保 tag 指向已合并的 release commit。
- 触发的 GitHub Actions 会显示**所有 job skipped** —— 属预期现象，因为 `build-image.yml` 只构建 `application-api` 镜像。

### 第 6 步：构建 & 上传（手动 —— 仅由用户执行）

1. 用 **DevEco Studio** 打开 `huawei/atomicservice/MFA`
2. `Build > Build Hap(s)/APP(s) > Build APP(s)`，使用 release 签名配置（`default` product、`release` build mode）
3. 取签名包：`huawei/atomicservice/MFA/build/outputs/default/MFA-default-signed.app`
4. AGC（AppGallery Connect）→ **我的应用** → **HarmonyOS** → 「应用信息」补全资料 → 「软件包管理」上传该 `.app`
5. 「版本信息」→「准备提交」→ **必须在该页面重新选择刚上传的软件包并保存**（只上传不选包时，提交的仍可能是旧包）
6. 「提交审核」→ 审核通过后发布（正式发布前可先走开放式测试）

**上传时常见的包解析错误：**

| 错误 | 原因 | 修正 |
|-------|-------|-----|
| Profile 文件非法 | 包是用属于其他应用的 Profile 签名的 | 使用*本*应用的 release Profile |
| 软件包使用的 Profile 和证书不匹配 | 签名证书 ≠ 申请 Profile 时使用的证书 | 重新检查 `build-profile.json5` 签名配置 |
| 非法软件包 | 包未签名 | 用签名配置重新构建；绝不要手动重新打包/重签 |
| 软件包中使用证书失效 | 证书被删除或已过期 | 重新申请证书后重新构建 |
| 错误码 1010（非元服务软件包） | 把 HarmonyOS **应用**包上传到了元服务应用 | 构建/签名 `atomicService` 包 |

- 元服务审核额外关注：快照、卡片大小、外部跳转 —— 见[《元服务审核指南》](https://developer.huawei.com/consumer/cn/doc/app/50129)
- 签名材料（`.p12` / `.cer` / `.p7b`）不在仓库内，仅存于本机；口令为 DevEco 写入的密文，换机通常不可直接复用。缺失时无法产出签名包 —— 属本地环境问题，需在 DevEco Studio 重新生成/配置签名。

**不要尝试自动化上传** —— AGC 需要交互式登录华为开发者账号。

## 发布流程

```
用户："Release huawei / 华为元服务发版"
  |
  v
检查 git diff main..HEAD -- huawei/  +  app.json5 版本号 vs 最新 tag
  |
  v
分析提交/diff → SemVer 提升 → 计算 versionCode
  |
  v
更新 AppScope/app.json5 + CHANGELOG.md（Keep a Changelog）
  |
  v
从 main 创建 release 分支，提交，推送
  |
  v
创建 PR
  |
  v
合并 PR（由用户合并，或获得明确授权后合并）
  |
  v
git pull main → 打 tag huawei-atomicservice-mfa/vX.Y.Z → 推送 tag
  |
  v
提醒用户：在 DevEco Studio 构建签名 .app，然后通过 AGC 上传
```

## 速查表

| 步骤 | 操作 | 目的 |
|------|--------|---------|
| 1. 检查 | `git status`、`git tag -l 'huawei-atomicservice-mfa/*'`、`grep version AppScope/app.json5` | 确认状态干净 & 待发布版本 |
| 2. 提升 | 编辑 `AppScope/app.json5`（`versionCode` + `versionName`）、`CHANGELOG.md` | 更新版本号和 changelog |
| 3. PR | 创建 PR，等待用户合并 | 审核与批准 |
| 4. Tag | `git tag huawei-atomicservice-mfa/vX.Y.Z` + 推送 | 标记 release commit |
| 5. 发布 | DevEco Studio 构建 → AGC 上传 → 提交审核 | 发布到 AppGallery |

## 常见错误

| 错误 | 出现原因 | 修正方式 |
|---------|---------------|-----|
| 提升 `oh-package.json5` 版本号而不是 `app.json5` | 照搬小程序流程 | 华为版本号只在 `AppScope/app.json5` |
| 忘记 `versionCode`，只提升 `versionName` | 以为 `versionName` 才是可见的那个 | AGC 会拒绝未递增的 versionCode —— 必须计算 `MAJOR*10000+MINOR*100+PATCH` |
| 写成 `## v1.4.0`（没有方括号、没有日期） | 沿用了迁移前的旧段落习惯 | 所有段落都使用 `## [X.Y.Z] - YYYY-MM-DD` |
| 照抄迁移过来的旧条目，保留其 `feat:` / `optimize:` 类型前缀 | 旧条目带类型前缀 | 新条目用朴素的中文行为描述 + ` (#PR)` |
| 上传了包但没在「版本信息」里选中它 | 上传看起来成功了 | 提交审核前，在版本页面重新选择并保存新包 |
| PR 合并前就打 tag | 打得太早 | 合并后先 `git pull origin main` 再打 tag |
| 推了 tag 后看到 CI skipped 就慌了 | workflow 监听 `**` | 全部 skipped 属预期；不存在 huawei 相关 job |
| 混入无关目录的改动 | 想当然认为分支只涉及 huawei | 用 `-- huawei/` 显式过滤 |
| 提交 `build/` 产物或 `.app` | 图省事把产物一起提交 | release PR 里只应有 `app.json5` + `CHANGELOG.md`（+ 锁文件） |
| 自动合并 PR | 想当然认为 release PR 是安全的 | 合并前等待用户明确确认 |
| 试图用脚本上传 AGC | 自动化惯性 | 需要交互式登录 —— 这一步只能手动 |

## 危险信号

**绝不：**
- 直推 main，或 force-push
- 自动合并 release PR
- 在 PR 合并前打 tag
- 复用 `versionCode`
- 在发布中改动 `bundleName` 或 `build-profile.json5` 签名材料
- 尝试自动化 AGC 上传
- 提交 `build/`、`oh_modules/`、`.hvigor/`、`.idea/`

**务必：**
- 核对 `app.json5` 中 `versionName` 等于 tag 版本号
- 把 release diff 限制在 `huawei/atomicservice/MFA/` 内
- 使用 `huawei-atomicservice-mfa/vX.Y.Z` tag 前缀
- 把签名 `.app` + AGC 上传步骤交给用户手动完成
