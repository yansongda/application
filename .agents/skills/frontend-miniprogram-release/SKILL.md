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

### 0. 判定基线：上一个已发布 tag（§3 分类与 §4 版本号共用）

**版本号与 CHANGELOG 分类回答的是同一个问题：相对上一个 release tag，变化是什么。commit message 与 PR 内的方案演进都不是基线。**

```bash
# 1) 确认基线 tag（按 semver 排序，取目标组件的最后一个）
git tag --list | grep '<component-prefix>/v' | sort -V | tail -3

# 2) 基线里有没有这个文件 / 目录？不存在 → 该功能属首次发版（CHANGELOG 归 Added，版本至少 MINOR）
git ls-tree -r --name-only <last-tag> -- <target-dir>/ | grep -F '<path/to/feature>'

# 3) 区间内提交（只是线索）与真实改动（事实）
git log <last-tag>..HEAD --oneline -- <target-dir>/
git show --stat <commit> -- <target-dir>/
git diff <last-tag>..HEAD -- <target-dir>/

# 4) 曾存在于未合并分支的旧实现（如端内加密 → 服务端加密）不算基线
git log --all --oneline -- <path/to/feature>
```

**commit message 只是线索，diff 才是事实。** 一个 `fix:` 提交可能只改了一处注释（无需提升版本），而一个 `chore:` 提交可能新增了一个页面（应提升 MINOR）。

| 相对基线 tag 的变化 | CHANGELOG 分类 | 版本提升 |
|---|---|---|
| 基线中不存在的新功能 / 新页面 / 新对外接口 | `Added` | **MINOR** |
| 基线中已存在，且做了有意的行为调整 | `Changed` | **MINOR**（无用户可见变化则不提升） |
| 基线中已存在，原本就是缺陷（含开发版专属展示问题） | `Fixed` | **PATCH** |
| 移除已发布能力 | `Removed` | **MINOR**；破坏向后兼容则 **MAJOR** |
| 纯内部重构 / 测试 / 注释 / 内部函数加参数 | 不单列 | 无用户可见变化则不发版，否则 **PATCH** |

**真实反例**：加密备份随 1.3.0 首次发布，commit message 为 `feat: 加密备份改用后端接口（移除端内实现）`；照 message 写成 `Changed: 备份加解密改为由服务端完成` 是错的——基线 tag 中根本没有备份功能，应为 `Added: 新增加密备份（加解密在服务端完成）`。

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

**分类（`Added` / `Changed` / `Fixed` / `Removed`）判定见 §0**：以已发布 tag 为基线，不按 commit message 或 PR 内方案演进归类。

### 4. 版本号判定

先按 **§0** 确认基线 tag，再看实际 diff（而不是 commit message）定级：基线中不存在的功能 → **MINOR**；既有缺陷修复 → **PATCH**；破坏向后兼容 → **MAJOR**。映射表见 §0。

**判定流程：**

1. 是否有新功能 / 新页面 / 新对外接口？ → **MINOR**
2. 否则是否有既有缺陷修复？ → **PATCH**
3. 是否全部是内部重构 / 清理？ → 无用户可见变化可跳过发版，打包发布则 **PATCH**
4. 是否破坏向后兼容（移除 API、改变响应格式）？ → **MAJOR**

### 5. 版本提升检查清单

创建 release PR 之前：

- [ ] 已通过 diff 分析确定新版本号（见 §4）
- [ ] 已更新 `package.json` 中的版本号
- [ ] 已按 §0 确认基线 tag，并据此判定版本号与 CHANGELOG 分类（每条 `Changed` 都能指出基线中已存在的旧行为，每条 `Fixed` 都是既有缺陷）
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
| 只按 commit message / PR 内方案演进判定 | message 是线索不是事实（`fix:` 可能只改注释；`feat:` 可能只是分支内换实现）；版本号与 CHANGELOG 分类因此判错 | 以已发布 tag 为基线查 `git ls-tree` / `git diff`（§0） |
| 把非 `Changed` 的内容写进 `Changed` | 拿 PR 内的方案变更（「改用 / 移除端内实现」）或「显示值变了」当行为设计变更 | 首次上线的新功能归 `Added`，既有缺陷修复归 `Fixed`（§0） |
| 等待期间把 TODO 留在 `in_progress` | 系统会不断催促继续 | 把阻塞/等待中的任务标记为 `completed` 并加说明，否则系统会反复提醒 |

## 发布流程

```
用户："Release wechat"
  |
  v
检查 git diff main..HEAD -- wechat/
  |
  v
确认基线 tag → 按 §0 判定分类与 SemVer 级别（patch/minor/major）
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
