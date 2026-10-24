---
name: repo-clean-commit-push
description: Enforce strict repository hygiene before commit/push: exclude heavy run artifacts, prevent duplicate script copies, commit only relevant source files, and verify local/remote sync.
---

## Quick Prompt

Use this single prompt:

`Use repo-clean-commit-push: <commit message>`

Example:

`Use repo-clean-commit-push: chore(weekly): sync scripts and skills, keep repo clean`

## Purpose

Use this skill when preparing a safe commit/push for this repository.

It enforces:
- Clean staging scope (scripts, automations, skills, docs only unless user explicitly asks otherwise)
- Exclusion of heavy runtime artifacts (validation outputs, logs, raw dumps, archives)
- Duplicate prevention (no copied/backup script variants)
- Local and remote sync verification after push

## Strict Workflow

1. Verify repo root and branch
- Ensure current git top-level is the project repository (not user home folder).
- Show `git status -sb` and current branch tracking.

2. Exclusion and cleanliness guard
- Confirm heavy runtime paths are ignored (especially `development/validation/`).
- Use `git status --short --ignored` to verify exclusions are active.
- Never stage validation outputs, generated CSVs, compressed run artifacts, or transient logs.

3. Duplicate guard (before staging)
- Check for duplicate script names under `Scripts/`.
- Check for obvious duplicate variants by filename pattern: `copy`, `old`, `backup`, `bak`, `(1)`, `_v2`.
- If duplicates exist, keep only the latest intentional canonical file and remove stale duplicates.

4. Stage only relevant changes
- Stage only requested/relevant assets, typically:
  - `Scripts/**/*.ps1`
  - `.github/skills/**`
  - Selected docs/config updates needed for hygiene
- Do not stage unrelated local environment files.

5. Commit and push
- Commit with user-provided message (or concise conventional message if not provided).
- Push to tracked upstream branch.

6. Post-push verification
- Confirm `git status -sb` is clean and branch is synced.
- Report exactly what was committed and what was intentionally excluded.

## Guardrails

- Do not use destructive git commands (`reset --hard`, `checkout --`) unless explicitly requested.
- Do not amend existing commits unless explicitly requested.
- Do not add generated validation/run outputs to source control.
- If repo root resolves incorrectly (for example to user home), fix by operating explicitly with `git -C <repo>`.

## Expected Output Summary

After running this skill, provide:
- Commit hash
- Files committed
- Confirmed exclusions (heavy artifacts not tracked)
- Sync state (`local == upstream`)
