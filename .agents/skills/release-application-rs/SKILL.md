---
name: release-application-rs
description: Use when releasing the application-rs Rust backend workspace, bumping workspace version, updating CHANGELOG, or creating Docker image tags
---

# Release Application-RS (Rust Backend)

## Overview

The Rust backend in this monorepo is a Cargo workspace that builds a Docker image via GitHub Actions on tag push. It does NOT publish to crates.io (`publish = false`).

**Core principle:** Bump version & changelog → **Create PR** → **User manually merges** → Tag & push (triggers Docker build).

**⚠️ MUST create PR. Never push directly to main.**
**⚠️ MUST NOT auto-merge the PR. The user must review and merge manually.**

## Prerequisites

- Git working directory clean
- On `main` branch
- All Rust CI checks passing (`cargo check`, `cargo fmt --check`, `cargo clippy`)

## The Process

### Step 1: Check Current State

```bash
# Must run from application-rs/ directory
cd application-rs

# Current workspace version
grep '^version = ' Cargo.toml

# Recent tags for application-api
git tag -l 'application-api/*' | sort -V | tail -5

# Check git status
git status --short
git branch --show-current
```

**Tag format:** `application-api/v<VERSION>` (triggers `.github/workflows/build-image.yml`)

**If dirty:** Stop. Commit or stash changes first.

### Step 2: Bump Version & Update CHANGELOG

**Determine the version bump by analyzing the actual code diff, not just commit messages.**

```bash
cd application-rs

# Step 1: List commits since last tag (reference only)
git log <PREV_TAG>..HEAD --oneline

# Step 2: Inspect each commit's actual changes (THIS is what matters)
git show --stat <commit>

# Step 3: Review the aggregate diff
git diff <PREV_TAG>..HEAD
```

**Commit messages are a hint; the diff is the truth.** A `fix:` commit may only touch a comment (no bump needed), while a `chore:` commit may introduce a new API (MINOR bump). Apply SemVer based on **behavioral impact**:

| What Changed | Version Bump | Example |
|--------------|-------------|---------|
| New user-facing feature / new API / new binary behavior | **MINOR** | `1.13.0` → `1.14.0` |
| Bug fix with behavior change | **PATCH** | `1.13.0` → `1.13.1` |
| Pure refactor / comment update / no behavior change | **No bump** or bundle with other changes | Skip if nothing user-visible changed |
| Breaking change (removed API, changed config format) | **MAJOR** | `1.13.0` → `2.0.0` |

**Decision flow:**

1. Does any commit add new user-visible functionality? → **MINOR**
2. Does any commit fix a bug that users experienced? → **PATCH** (if no MINOR)
3. Are all changes internal refactors / cleanups? → **PATCH** if bundling, otherwise consider skipping release
4. Does any commit break backward compatibility? → **MAJOR**

**Update `application-rs/Cargo.toml` (workspace root only):**

```toml
[workspace.package]
version = "X.Y.Z"  # Bump this
```

Since all sub-crates use `version.workspace = true`, only the workspace root needs updating. Always run `cargo update` (or any build command) to regenerate `Cargo.lock`, then commit it.

**Update `application-rs/CHANGELOG.md`:**

Follow [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) format:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New feature description (#PR) ([commit](https://github.com/yansongda/application/commit/abc123))

### Changed
- Behavior changes (#PR) ([commit](https://github.com/yansongda/application/commit/def456))

### Fixed
- Bug fixes (#PR) ([commit](https://github.com/yansongda/application/commit/ghi789))
```

**Format checklist:**
- [ ] Version: `## [X.Y.Z] - YYYY-MM-DD` (NOT `## vX.Y.Z`)
- [ ] Section headers capitalized: `### Added`, `### Changed`, `### Fixed`
- [ ] Each entry has PR number and commit link
- [ ] New version added at the **TOP** of the file

**Get commits since last release:**
```bash
cd application-rs
git log <PREV_TAG>..HEAD --pretty=format:"- %s ([%h](https://github.com/yansongda/application/commit/%h))"
```

### Step 3: Verify Rust Code Quality

Before creating PR, ensure all checks pass:

```bash
cd application-rs
cargo check --all-features
cargo fmt --all -- --check
cargo clippy -- -D warnings
```

### Step 4: Create PR

```bash
git checkout -b release/application-rs-vX.Y.Z
git add application-rs/Cargo.toml application-rs/Cargo.lock application-rs/CHANGELOG.md
git commit -m "release(application-rs): vX.Y.Z"
git push origin release/application-rs-vX.Y.Z
gh pr create --title "release(application-rs): vX.Y.Z" --body "Release application-rs vX.Y.Z"
```

**Wait for the user to manually review and merge the PR. NEVER auto-merge.**

### Step 5: Tag & Push (After PR Merge)

```bash
git checkout main && git pull origin main

# Create tag with application-api prefix
git tag application-api/vX.Y.Z
git push origin application-api/vX.Y.Z
```

**⚠️ Tag format must match workflow trigger:**
- The workflow `.github/workflows/build-image.yml` checks `startsWith(github.ref, 'refs/tags/application-api')`
- Tag format: `application-api/vX.Y.Z`
- The workflow converts `/` to `-` for Docker image tags automatically

### Step 6: Verify Docker Build

- GitHub Actions: https://github.com/yansongda/application/actions
- Check that `build-image.yml` workflow runs successfully
- Images are pushed to: Aliyun, DockerHub, GitHub Container Registry

## Quick Reference

| Step | Action | Purpose |
|------|--------|---------|
| 1. Check | `git status`, `git tag`, check version | Verify clean state |
| 2. Bump | Edit `Cargo.toml`, `CHANGELOG.md` | Update version and changelog |
| 3. Verify | `cargo check`, `cargo fmt`, `cargo clippy` | Ensure code quality |
| 4. PR | Create PR, wait for merge | Review & approve |
| 5. Tag | `git tag application-api/vX.Y.Z` | Trigger Docker build |
| 6. Verify | Check GitHub Actions | Confirm image built |

## Common Mistakes

**Wrong tag format**
- **Problem:** Tag `v1.0.0` won't trigger the workflow
- **Fix:** Must use `application-api/v1.0.0`

**Bumping individual crate versions**
- **Problem:** Editing `application-api/Cargo.toml` directly when it uses `version.workspace = true`
- **Fix:** Only bump workspace root `Cargo.toml`

**Forgetting to run Rust checks**
- **Problem:** PR fails CI due to `cargo fmt` or `cargo clippy` errors
- **Fix:** Always run all three checks before creating PR

**Bumping version based only on commit messages**
- **Problem:** A `fix:` commit might only touch a comment (no bump needed), while a `chore:` commit might add a new API (MINOR bump)
- **Fix:** Always inspect `git show --stat` and `git diff` to determine actual behavioral impact; commit messages are hints, the diff is the truth

**Tagging before PR merge**
- **Problem:** Tag points to pre-merge commit
- **Fix:** Always `git pull origin main` after merge before tagging

**Direct-pushing to main**
- **Problem:** Bypasses review and branch protection
- **Fix:** Always create PR, even for version bumps

## Workspace Structure Reminder

```
application-rs/
  Cargo.toml           # Workspace root - bump version here
  Cargo.lock           # Commit if changed
  CHANGELOG.md         # Update with new release notes
  application-api/     # Binary crate (HTTP API)
  application-database/# Database layer
  application-kernel/  # Core types, config, errors
  application-macro/   # Procedural macros
  application-util/    # HTTP client, 3rd party integrations
```

All crates share the workspace version via `version.workspace = true`.

## Red Flags

**Never:**
- Auto-merge the PR (user MUST review manually)
- Push directly to main
- Tag before PR merge
- Skip `cargo fmt` / `cargo clippy` checks
- Release from dirty working directory
- Use wrong tag format (`v1.0.0` instead of `application-api/v1.0.0`)
- Bump version based only on commit messages instead of inspecting the actual diff

**Always:**
- Run all Rust checks before PR
- Update workspace root `Cargo.toml` only
- Use `application-api/vX.Y.Z` tag format
- Wait for PR merge before tagging
