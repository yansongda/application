---
name: release-huawei-atomicservice
description: Use when releasing the Huawei atomic service (元服务) frontend under huawei/atomicservice/MFA — bumping AppScope/app.json5 versionCode/versionName, adding a CHANGELOG.md section, creating a release PR, tagging huawei-atomicservice-mfa/vX.Y.Z, or preparing the signed .app for AGC (AppGallery Connect) 上架
---

# Release Huawei Atomic Service (华为元服务 MFA)

## Overview

The Huawei atomic service frontend lives in `huawei/atomicservice/MFA/` and is built with ArkTS/ETS.

**Key difference from the WeChat mini-programs:** the version is NOT in `package.json` / `oh-package.json5` — it lives in `AppScope/app.json5` as `versionCode` + `versionName`. And there is **no CI** for this project: packaging and 上架 are manual DevEco Studio + AGC steps.

**Core principle:** bump version & CHANGELOG → **Create PR** → **User manually merges** → Tag & push → **manual** DevEco Studio build + AGC upload.

**⚠️ MUST create a PR. Never push directly to main.**
**⚠️ MUST NOT auto-merge the PR. The user must review and merge manually.**
**⚠️ MUST NOT attempt automated AGC upload** (requires interactive Huawei developer account login).

## When to Use

- Releasing a new version of the Huawei atomic service (华为元服务 MFA)
- Bumping `versionCode` / `versionName` in `huawei/atomicservice/MFA/AppScope/app.json5`
- Adding a CHANGELOG section for the huawei frontend
- Creating or pushing tag `huawei-atomicservice-mfa/vX.Y.Z`
- Preparing the signed `.app` package for AGC 上架

Not for: WeChat mini-programs (**REQUIRED:** use frontend-miniprogram-release), the Rust backend (**REQUIRED:** use release-application-rs).

## Key Facts (verified in this repo)

| Item | Value |
|------|-------|
| Project root | `huawei/atomicservice/MFA/` |
| Version source | `AppScope/app.json5` → `"versionCode": <int>`, `"versionName": "X.Y.Z"` |
| versionCode scheme | `MAJOR*10000 + MINOR*100 + PATCH` (v1.0.0 = `10000`, v1.3.1 = `10301`) |
| CHANGELOG | `huawei/atomicservice/MFA/CHANGELOG.md` (Keep a Changelog) |
| Tag format | `huawei-atomicservice-mfa/vX.Y.Z` (lightweight tags) |
| Bundle | `com.atomicservice.6917576589568238756`, `bundleType: atomicService` |
| Signed package | `huawei/atomicservice/MFA/build/outputs/default/MFA-default-signed.app` (build output, never committed) |
| Build & upload | DevEco Studio GUI + AGC web console — no `hvigorw` CLI wrapper is committed |
| CI | none for huawei. Pushing the tag still triggers `.github/workflows/build-image.yml` (it listens to `**`), but every job is skipped by its `application-api` guard — an all-skipped run is **expected**, not a failure. |

## The Process

### Step 1: Check Current State

```bash
cd huawei/atomicservice/MFA

git status --short
git branch --show-current
git tag -l 'huawei-atomicservice-mfa/*' | sort -V | tail -5
grep -E 'versionCode|versionName' AppScope/app.json5
```

**If dirty:** Stop and look at *what* is dirty:
- Changes inside `huawei/atomicservice/MFA/` that belong to this release (pending version bump, CHANGELOG entries) → keep them and carry them into the release branch and commit
- Anything else (unrelated work in progress) → commit or stash it first, and keep it out of the release PR

Never discard or stash-drop release-related edits to make the tree clean.

**Scope isolation (CRITICAL).** The current branch is often a feature branch with unrelated work:

```bash
# WRONG: Includes all changes from the branch
git diff main..HEAD --stat

# RIGHT: Only check changes in the target directory
git diff main..HEAD -- huawei/
```

`versionName` in `app.json5` is sometimes bumped together with feature work, so it may already be **ahead of the newest tag** (example, 2026-09 state: HEAD has `1.4.0` / `10400` while the newest tag is `v1.3.1`). In that case the pending version is `1.4.0` and the release PR only needs the CHANGELOG section.

### Step 2: Determine the Version

**Commit messages are a hint; the diff is the truth.**

```bash
# Step 1: List commits since last tag (reference only)
git log <PREV_TAG>..HEAD --oneline -- huawei/

# Step 2: Inspect each commit's actual changes (THIS is what matters)
git show --stat <commit> -- huawei/

# Step 3: Review the aggregate diff
git diff <PREV_TAG>..HEAD -- huawei/
```

A `chore:` commit may add a whole page (MINOR), a `feat:` commit may only touch a string resource (PATCH). Apply [SemVer](https://semver.org/lang/zh-CN/) based on **behavioral impact**:

| What Changed | Version Bump | Example |
|--------------|-------------|---------|
| New user-facing page / feature / API call | **MINOR** | `1.3.1` → `1.4.0` |
| Bug fix with behavior change | **PATCH** | `1.3.0` → `1.3.1` |
| Pure refactor / comment or resource renames | **No bump** or bundle with other changes | Skip if nothing user-visible changed |
| Breaking change (removed page, changed auth flow) | **MAJOR** | `1.3.1` → `2.0.0` |

Then compute `versionCode` from the target version — it is **not** an independent counter:

```
versionCode = MAJOR * 10000 + MINOR * 100 + PATCH
```

- `1.4.0` → `10400`, `1.3.1` → `10301`, `2.0.0` → `20000`
- **Never reuse a versionCode.** AGC rejects an upload whose versionCode is not greater than the already-published one, so even a PATCH bump needs a new number.

### Step 3: Update `app.json5` & `CHANGELOG.md`

**`AppScope/app.json5`** — change only these two lines:

```json5
{
  "app": {
    "bundleName": "com.atomicservice.6917576589568238756",
    "bundleType": "atomicService",
    "vendor": "yansongda",
    "versionCode": 10400,        // MAJOR*10000 + MINOR*100 + PATCH
    "versionName": "1.4.0",      // must equal the tag version
    "icon": "$media:icon",
    "label": "$string:app_name",
    "description": "$string:app_description"
  }
}
```

Never touch `bundleName` (AGC matches the package to the app by it) and never touch the signing config in `build-profile.json5` (local absolute paths + DevEco-encrypted passwords; changing them invalidates the signature).

**`CHANGELOG.md`** — [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) format, same as `wechat/miniprogram/yansongda` and `wechat/miniprogram/totp`:

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

**Format checklist:**
- [ ] Version header: `## [X.Y.Z] - YYYY-MM-DD` (NOT `## vX.Y.Z`, never omit the date)
- [ ] Section headers capitalized English, one per change type: `### Added` / `### Changed` / `### Deprecated` / `### Removed` / `### Fixed` / `### Security`
- [ ] One-line Chinese entries describing **user-visible behavior**, append `(#PR)` when a PR number exists
- [ ] New version section at the **TOP** of the file
- [ ] Keep the `# Changelog` title + convention line at the top of the file
- [ ] Date is the actual release date — read it with `date +%F`; never invent or copy it
- [ ] Every heading in the file uses `## [X.Y.Z] - YYYY-MM-DD` — never add a `## vX.Y.Z` heading; if an old-format heading is still present, convert it in the same commit

**Get commits since last release:**
```bash
git log <PREV_TAG>..HEAD --pretty=format:"- %s" -- huawei/
```

If dependencies changed, also stage `oh-package.json5` + `oh-package-lock.json5` (the lock file must always be committed).

### Step 4: Create the Release PR

```bash
git checkout main && git pull origin main
git checkout -b release/huawei-atomicservice-vX.Y.Z
git add huawei/atomicservice/MFA/AppScope/app.json5 huawei/atomicservice/MFA/CHANGELOG.md
git commit -m "release(huawei): vX.Y.Z"
git push -u origin release/huawei-atomicservice-vX.Y.Z
gh pr create --title "release(huawei): vX.Y.Z" --body "Release huawei atomic service vX.Y.Z"
```

- If the version was already bumped by feature work, only `CHANGELOG.md` is staged — say so in the PR body.
- Since there is no CI lint/build for huawei, open the project once in DevEco Studio and make sure it compiles (and code-linter is clean) before opening the PR.
- **Wait for the user to manually review and merge. NEVER auto-merge.**
- Never `git push` to main; never force-push.

### Step 5: Tag & Push (After PR Merge)

```bash
git checkout main && git pull origin main

git tag huawei-atomicservice-mfa/vX.Y.Z
git push origin huawei-atomicservice-mfa/vX.Y.Z
```

- Lightweight tag; the `huawei-atomicservice-mfa/` prefix is mandatory and must match the existing tags exactly.
- Always pull latest main first so the tag points at the merged release commit.
- The triggered GitHub Actions run will show **all jobs skipped** — expected, because `build-image.yml` only builds `application-api` images.

### Step 6: Build & Upload (MANUAL — user only)

1. Open `huawei/atomicservice/MFA` in **DevEco Studio**
2. `Build > Build Hap(s)/APP(s) > Build APP(s)` with the release signing config (`default` product, `release` build mode)
3. Take the signed package at `huawei/atomicservice/MFA/build/outputs/default/MFA-default-signed.app`
4. AGC (AppGallery Connect) → **我的应用** → **HarmonyOS** → 「应用信息」补全资料 → 「软件包管理」上传该 `.app`
5. 「版本信息」→「准备提交」→ **必须在该页面重新选择刚上传的软件包并保存**（只上传不选包时，提交的仍可能是旧包）
6. 「提交审核」→ 审核通过后发布（正式发布前可先走开放式测试）

**Common package-parse errors at upload time:**

| Error | Cause | Fix |
|-------|-------|-----|
| Profile 文件非法 | Package was signed with a Profile belonging to another app | Use the release Profile of *this* app |
| 软件包使用的 Profile 和证书不匹配 | Signing certificate ≠ certificate used when applying for the Profile | Re-check `build-profile.json5` signing config |
| 非法软件包 | Package not signed | Rebuild with the signing config; never re-pack/re-sign manually |
| 软件包中使用证书失效 | Certificate deleted or expired | Re-apply for the certificate and rebuild |
| 错误码 1010（非元服务软件包） | Uploaded a HarmonyOS **application** package into a 元服务 app | Build/sign the `atomicService` package |

- 元服务审核额外关注：快照、卡片大小、外部跳转 —— 见[《元服务审核指南》](https://developer.huawei.com/consumer/cn/doc/app/50129)
- 签名材料（`.p12` / `.cer` / `.p7b`）不在仓库内，仅存于本机；口令为 DevEco 写入的密文，换机通常不可直接复用。缺失时无法产出签名包 —— 属本地环境问题，需在 DevEco Studio 重新生成/配置签名。

**Do not attempt automated upload** — AGC requires an interactive Huawei developer account login.

## Release Flow

```
User: "Release huawei / 华为元服务发版"
  |
  v
Check git diff main..HEAD -- huawei/  +  app.json5 version vs newest tag
  |
  v
Analyze commits/diff → SemVer bump → compute versionCode
  |
  v
Update AppScope/app.json5 + CHANGELOG.md (Keep a Changelog)
  |
  v
Create release branch from main, commit, push
  |
  v
Create PR
  |
  v
Merge PR (user, or with explicit permission)
  |
  v
git pull main → tag huawei-atomicservice-mfa/vX.Y.Z → push tag
  |
  v
Inform user: build signed .app in DevEco Studio, then upload via AGC
```

## Quick Reference

| Step | Action | Purpose |
|------|--------|---------|
| 1. Check | `git status`, `git tag -l 'huawei-atomicservice-mfa/*'`, `grep version AppScope/app.json5` | Verify clean state & pending version |
| 2. Bump | Edit `AppScope/app.json5` (`versionCode` + `versionName`), `CHANGELOG.md` | Update version and changelog |
| 3. PR | Create PR, wait for user merge | Review & approve |
| 4. Tag | `git tag huawei-atomicservice-mfa/vX.Y.Z` + push | Mark the release commit |
| 5. Ship | DevEco Studio build → AGC upload → 提交审核 | Publish to AppGallery |

## Common Mistakes

| Mistake | Why It Happens | Fix |
|---------|---------------|-----|
| Bumping `oh-package.json5` version instead of `app.json5` | Copying the mini-program workflow | Huawei version lives in `AppScope/app.json5` only |
| Forgetting `versionCode`, bumping only `versionName` | `versionName` is the visible one | AGC rejects a non-increased versionCode — always compute `MAJOR*10000+MINOR*100+PATCH` |
| Writing `## v1.4.0` (no brackets, no date) | Habit from the pre-migration sections | All sections use `## [X.Y.Z] - YYYY-MM-DD` |
| Copying a migrated entry verbatim, keeping its `feat:` / `optimize:` type prefix | The old entries had type prefixes | New entries are plain Chinese behavior descriptions + ` (#PR)` |
| Uploading the package but not selecting it in 「版本信息」 | Upload looks successful | Re-select and save the new package in the version page before 提交审核 |
| Tagging before PR merge | Tagging too early | `git pull origin main` after merge, then tag |
| Pushing the tag and panicking at a skipped CI run | Workflow listens to `**` | All jobs skipped is expected; no huawei job exists |
| Including unrelated directory changes | Assuming the branch is only about huawei | Explicitly filter with `-- huawei/` |
| Committing `build/` output or the `.app` | Bundling the artifact "for convenience" | Only `app.json5` + `CHANGELOG.md` (+ lock files) belong in the release PR |
| Auto-merging the PR | Assuming release PRs are safe | Wait for explicit user confirmation before merging |
| Trying to upload to AGC via script | Automation instinct | Interactive login required — this step is manual |

## Red Flags

**Never:**
- Push directly to main, or force-push
- Auto-merge the release PR
- Tag before the PR is merged
- Reuse a `versionCode`
- Change `bundleName` or `build-profile.json5` signing material as part of a release
- Attempt an automated AGC upload
- Commit `build/`, `oh_modules/`, `.hvigor/`, `.idea/`

**Always:**
- Verify `versionName` in `app.json5` equals the tag version
- Keep the release diff limited to `huawei/atomicservice/MFA/`
- Use the `huawei-atomicservice-mfa/vX.Y.Z` tag prefix
- Hand the signed `.app` + AGC upload step to the user
