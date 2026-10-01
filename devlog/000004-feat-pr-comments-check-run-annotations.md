# 000004: Check-run annotations in agent-review-pr-comments

**Status:** in progress (branch `feat/pr-comments-check-run-annotations`)
**Intent:** Retrieve check-run annotations (such as Xcode Cloud, App Store Connect, compiler diagnostics, and linter notices) in addition to review comments and issue comments, so inline feedback surfaced on the GitHub diff tab is triaged and addressed.

## Decisions

- 2026-09-30T23:37-0700 Check-run annotations are fetched via GitHub API endpoints `/repos/{owner}/{repo}/commits/<triage_sha>/check-runs` and `/repos/{owner}/{repo}/check-runs/{check_run_id}/annotations`.
- 2026-09-30T23:37-0700 Gated to check-runs reporting `annotations_count > 0` to minimize unnecessary API round trips.
- 2026-09-30T23:37-0700 Annotations rendered with format `ANNOTATION [<level>] <path>:<line> by <check_suite_name>:\n<message>\n` to mirror the existing `DIFF`, `REVIEW`, and `ISSUE` diagnostic formats.
- 2026-09-30T23:37-0700 Verification suite updated in `tests/verify-install.sh` for API query count and scratch redirect count (3 to 5).

## What Changed

- `skills/agent-review-pr-comments/SKILL.md`:
  - Updated frontmatter description and introductory overview to include check-run annotations.
  - Updated prerequisites to note that Section 1A resolves `<pr_number>` and `<triage_sha>`.
  - Added check-run query and annotation extraction in Section 1A bash snippet.
  - Updated Section 1B triage instructions to cover check-run annotations.
- `tests/verify-install.sh`:
  - Updated `pr url quoted: prc` assertion from 3 to 5.
  - Updated `scratch redirects guarded: prc` assertion from 3 to 5.

## Verification

- `./tests/verify-install.sh`: 956 passed, 0 failed.
- Checked ASCII compliance: pure ASCII, zero em dashes.
