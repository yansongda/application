---
name: frontend-miniprogram-release
description: Use when releasing a WeChat mini-program from a monorepo, especially when creating release PRs, bumping versions, updating CHANGELOGs, or creating version tags
---

# Frontend Mini-Program Release

## Overview

Releasing a mini-program frontend in a monorepo requires careful scope isolation and PR-based workflows. One wrong direct-push to main can require force-push gymnastics.

## When to Use

- Bumping version in `package.json` for a mini-program
- Creating a release commit with version + CHANGELOG updates
- Preparing a mini-program for upload to WeChat platform
- Working in a monorepo where multiple frontends share a single git repository

## Core Rules

### 1. Scope Isolation (CRITICAL)

**Always confirm which directory the user wants to release.**

```bash
# WRONG: Includes all changes from the branch
git diff main..HEAD --stat

# RIGHT: Only check changes in the target directory
git diff main..HEAD -- wechat/
```

- If the release branch contains changes outside the target directory, **cherry-pick or checkout only the target directory** into a fresh branch from main
- Never assume "the current branch" equals "only the changes the user cares about"

### 2. Never Direct-Push to Protected Branches

**Version bumps and release commits must go through PR, just like feature code.**

```bash
# WRONG
 git commit -m "release: v1.x.x"
git push origin main

# RIGHT
git checkout -b release/wechat-v1.x.x
git commit -m "release(wechat): v1.x.x"
git push -u origin release/wechat-v1.x.x
# Then create PR and merge via GitHub
```

- Even if you have force-push permissions, **don't use them for release commits**
- If you accidentally pushed to main, use `git revert` + PR instead of force-push to bypass branch protection

### 3. CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/) (Chinese version supported):

```markdown
# Changelog

本文件遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范。

## [1.14.0] - YYYY-MM-DD

### Added
- New feature description (#101)

### Fixed
- Bug fix related to the new feature (#102)

## [1.13.1] - YYYY-MM-DD

### Fixed
- Bug fix description (#99)

### Changed
- Refactor or directory migration (#98)

## [1.13.0] - YYYY-MM-DD
```

- Use `[SemVer]` version numbers with brackets
- Use `### Added / Changed / Fixed / Removed` categories
- Include PR numbers where applicable: `(#101)`
- Always add the new version section at the TOP of the file
- When a release contains multiple commit types, list each under its own category

### 4. Version Number Analysis

Before bumping, determine the new version by **analyzing the actual diff**, not just commit messages:

```bash
# Step 1: List commits since last tag (reference only)
git log <last-tag>..HEAD --oneline -- <target-dir>/

# Step 2: Inspect each commit's actual changes (THIS is what matters)
git show --stat <commit> -- <target-dir>/

# Step 3: Review the aggregate diff
git diff <last-tag>..HEAD -- <target-dir>/
```

**Commit messages are a hint, diff is the truth.** A `fix:` commit might only touch a comment (no version bump needed), while a `chore:` commit might add a new page (MINOR bump).

Apply [SemVer](https://semver.org/lang/zh-CN/) based on **behavioral impact**:

| What Changed | Version Bump | Example |
|--------------|-------------|---------|
| New user-facing feature / new page / new API | **MINOR** | `1.13.0` → `1.14.0` |
| Bug fix with behavior change | **PATCH** | `1.13.0` → `1.13.1` |
| Pure refactor / comment update / no behavior change | **No bump** or bundle with other changes | Skip if nothing user-visible changed |
| Breaking change (removed API, changed response format) | **MAJOR** | `1.13.0` → `2.0.0` |

**Decision flow:**

1. Does any commit add new user-visible functionality? → **MINOR**
2. Does any commit fix a bug that users experienced? → **PATCH** (if no MINOR)
3. Are all changes internal refactors / cleanups? → **PATCH** if bundling, otherwise consider skipping release
4. Does any commit break backward compatibility? → **MAJOR**

### 5. Version Bump Checklist

Before creating the release PR:

- [ ] New version number determined via diff analysis (see §4)
- [ ] `package.json` version updated
- [ ] `CHANGELOG.md` updated with new section, categorized by change type
- [ ] Lock file (`pnpm-lock.yaml` / `package-lock.json`) updated if dependencies changed
- [ ] Only target directory files are included in the commit
- [ ] Commit message follows repo convention: `release(wechat): v1.x.x`

## Common Mistakes

| Mistake | Why It Happens | Fix |
|---------|---------------|-----|
| Direct-pushing release to main | "It's just a version bump" | Treat version bumps like any other code change |
| Including unrelated directory changes | Assuming branch only has relevant changes | Explicitly filter by target directory |
| Force-pushing after accidental push | Trying to "clean up" history | Use `git revert` + PR instead |
| Wrong CHANGELOG format | Copying old inconsistent format | Use Keep a Changelog standard |
| Auto-merging PR without user consent | Assuming release PRs are safe to auto-merge | Always wait for explicit user confirmation before merging |
| Bumping version based only on commit messages | `fix:` might be a comment edit; `chore:` might add a new page | Always inspect `git show --stat` and `git diff` to determine actual behavioral impact |
| Leaving TODO items as `in_progress` while waiting | System continuously prompts for continuation | Mark blocking/waiting tasks as `completed` with a note, or the system will nag |

## Release Flow

```
User: "Release wechat"
  |
  v
Check git diff main..HEAD -- wechat/
  |
  v
Analyze commits → determine SemVer bump (patch/minor/major)
  |
  v
Create release branch from main
  |
  v
Bump version + update CHANGELOG
  |
  v
Commit and push release branch
  |
  v
Create PR
  |
  v
Merge PR (by user or with explicit permission)
  |
  v
Pull latest main and create tag: wechat-miniprogram-yansongda/v1.x.x
  |
  v
Push tag to origin
  |
  v
Inform user to upload via WeChat DevTools
```

## Tag Creation

After the release PR is merged, create a version tag:

```bash
# Pull latest main first
git checkout main && git pull origin main

# Create tag
git tag wechat-miniprogram-yansongda/v1.x.x

# Push tag
git push origin wechat-miniprogram-yansongda/v1.x.x
```

- Tag format: `wechat-miniprogram-yansongda/v{semver}`
- Always pull latest main before tagging to ensure tag points to the merged release commit
- Push tag immediately after creation
- If `git pull` is not a fast-forward, resolve conflicts first (rare for release branches)

## Platform Upload (Manual Step)

After PR is merged and tag is pushed, the user must manually:

1. Open WeChat DevTools
2. Compile and verify
3. Click **Upload** (or 工具 → 上传)
4. Enter version number and notes
5. Submit for review on the platform admin page

**Do not attempt automated upload** — platform authentication requires manual login.
