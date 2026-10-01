---
name: frontend-miniprogram-release
description: 在 monorepo 中发布微信小程序时使用，尤其是创建 release PR、提升版本号、更新 CHANGELOG 或创建版本 tag 的场景
---

# 微信小程序发布（Frontend Mini-Program Release）

## 概述

在 monorepo 中发布小程序前端，需要严格控制改动范围并走 PR 流程。一次错误地直推 main，可能就得靠 force-push 来收拾残局。

## 适用场景

- 为小程序更新 `package.json` 中的版本号
- 创建包含版本号 + CHANGELOG 更新的 release commit
- 准备将小程序上传到微信平台
- 在多个前端共享同一个 git 仓库的 monorepo 中工作

## 核心规则

### 1. 隔离改动范围（关键）

**始终先确认用户想发布的是哪个目录。**

```bash
# 错误：包含了分支上的所有改动
git diff main..HEAD --stat

# 正确：只检查目标目录中的改动
git diff main..HEAD -- wechat/
```

- 如果待发布分支包含目标目录之外的改动，**只把目标目录 cherry-pick 或 checkout** 到从 main 新建的分支上
- 永远不要假设“当前分支”就等于“用户关心的改动”

### 2. 绝不直推受保护分支

**版本号提升和 release commit 必须走 PR，与功能代码一视同仁。**

```bash
# 错误
 git commit -m "release: v1.x.x"
git push origin main

# 正确
git checkout -b release/wechat-v1.x.x
git commit -m "release(wechat): v1.x.x"
git push -u origin release/wechat-v1.x.x
# 然后在 GitHub 上创建 PR 并合并
```

- 即使你有 force-push 权限，**也不要把它用在 release commit 上**
- 如果不小心推到了 main，应使用 `git revert` + PR，而不是用 force-push 绕过分支保护

### 3. CHANGELOG 格式

遵循 [Keep a Changelog](https://keepachangelog.com/) 规范（支持中文版）：

```markdown
# Changelog

本文件遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范。

## [1.14.0] - YYYY-MM-DD

### Added
- 新功能描述 (#101)

### Fixed
- 与新功能相关的缺陷修复 (#102)

## [1.13.1] - YYYY-MM-DD

### Fixed
- 缺陷修复描述 (#99)

### Changed
- 重构或目录迁移 (#98)

## [1.13.0] - YYYY-MM-DD
```

- 版本号使用带方括号的 `[SemVer]` 格式
- 使用 `### Added / Changed / Fixed / Removed` 分类
- 尽可能附上 PR 编号：`(#101)`
- 新版本段落始终加在文件**最上方**
- 一次发布包含多种类型的提交时，每种类型各列在自己的分类下

### 4. 版本号判定

提升版本前，必须通过**分析实际 diff** 来决定新版本号，而不是只看 commit message：

```bash
# 第 1 步：列出上个 tag 之后的提交（仅供参考）
git log <last-tag>..HEAD --oneline -- <target-dir>/

# 第 2 步：查看每个提交的实际改动（这才是关键依据）
git show --stat <commit> -- <target-dir>/

# 第 3 步：审查整体 diff
git diff <last-tag>..HEAD -- <target-dir>/
```

**commit message 只是线索，diff 才是事实。** 一个 `fix:` 提交可能只改了一处注释（无需提升版本），而一个 `chore:` 提交可能新增了一个页面（应提升 MINOR）。

根据**行为影响**套用 [SemVer](https://semver.org/lang/zh-CN/)：

| 改动内容 | 版本提升 | 示例 |
|--------------|-------------|---------|
| 新增面向用户的功能 / 新页面 / 新 API | **MINOR** | `1.13.0` → `1.14.0` |
| 有行为变化的缺陷修复 | **PATCH** | `1.13.0` → `1.13.1` |
| 纯重构 / 注释修改 / 无行为变化 | **不提升** 或与其他改动合并发布 | 若无用户可见变化，可跳过发版 |
| 破坏性变更（移除 API、改变响应格式） | **MAJOR** | `1.13.0` → `2.0.0` |

**判定流程：**

1. 是否有提交新增了用户可见功能？ → **MINOR**
2. 是否有提交修复了用户实际遇到的问题？ → **PATCH**（若无 MINOR）
3. 是否所有改动都是内部重构 / 清理？ → 若打包发布则 **PATCH**，否则可考虑跳过本次发版
4. 是否有提交破坏向后兼容？ → **MAJOR**

### 5. 版本提升检查清单

创建 release PR 之前：

- [ ] 已通过 diff 分析确定新版本号（见 §4）
- [ ] 已更新 `package.json` 中的版本号
- [ ] 已更新 `CHANGELOG.md`，新增段落并按变更类型分类
- [ ] 若依赖有变化，已更新锁文件（`pnpm-lock.yaml` / `package-lock.json`）
- [ ] 提交中只包含目标目录的文件
- [ ] commit message 遵循仓库约定：`release(wechat): v1.x.x`

## 常见错误

| 错误 | 出现原因 | 修正方式 |
|---------|---------------|-----|
| 把 release 直推到 main | “只是改了个版本号而已” | 把版本提升当作普通代码改动对待 |
| 混入无关目录的改动 | 想当然认为分支上只有相关改动 | 显式按目标目录过滤 |
| 误推之后用 force-push 补救 | 想“清理”提交历史 | 改用 `git revert` + PR |
| CHANGELOG 格式不规范 | 沿用了旧的、不一致的格式 | 使用 Keep a Changelog 标准格式 |
| 未经用户同意自动合并 PR | 想当然认为 release PR 可以安全自动合并 | 合并前必须等待用户明确确认 |
| 只看 commit message 决定版本号 | `fix:` 可能只是改注释；`chore:` 可能新增页面 | 必须检查 `git show --stat` 和 `git diff` 判断实际行为影响 |
| 等待期间把 TODO 留在 `in_progress` | 系统会不断催促继续 | 把阻塞/等待中的任务标记为 `completed` 并加说明，否则系统会反复提醒 |

## 发布流程

```
用户："Release wechat"
  |
  v
检查 git diff main..HEAD -- wechat/
  |
  v
分析提交 → 确定 SemVer 提升级别（patch/minor/major）
  |
  v
从 main 创建 release 分支
  |
  v
提升版本号 + 更新 CHANGELOG
  |
  v
提交并推送 release 分支
  |
  v
创建 PR
  |
  v
合并 PR（由用户合并，或获得明确授权后合并）
  |
  v
拉取最新 main 并创建 tag：wechat-miniprogram-yansongda/v1.x.x
  |
  v
推送 tag 到 origin
  |
  v
提醒用户通过微信开发者工具上传
```

## 创建 Tag

release PR 合并后，创建版本 tag：

```bash
# 先拉取最新 main
git checkout main && git pull origin main

# 创建 tag
git tag wechat-miniprogram-yansongda/v1.x.x

# 推送 tag
git push origin wechat-miniprogram-yansongda/v1.x.x
```

- tag 格式：`wechat-miniprogram-yansongda/v{semver}`
- 打 tag 前务必先拉取最新 main，确保 tag 指向已合并的 release commit
- tag 创建后立即推送
- 若 `git pull` 不是 fast-forward，先解决冲突（release 分支极少出现）

## 平台上传（手动步骤）

PR 合并、tag 推送后，需要用户手动完成：

1. 打开微信开发者工具
2. 编译并验证
3. 点击**上传**（或 工具 → 上传）
4. 填写版本号和备注
5. 在平台管理后台提交审核

**不要尝试自动化上传** —— 平台鉴权需要人工登录。
