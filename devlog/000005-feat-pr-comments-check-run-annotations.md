# 000005: Check-run annotations in agent-review-pr-comments

**Status:** PR submitted (PR #7, branch `feat/pr-comments-check-run-annotations`)
**Intent:** Retrieve check-run annotations (such as Xcode Cloud, App Store Connect, compiler diagnostics, and linter notices) in addition to review comments and issue comments, so inline feedback surfaced on the GitHub diff tab is triaged and addressed.

## Decisions

- 2026-09-30T23:37-0700 Check-run annotations are fetched via GitHub API endpoints `/repos/{owner}/{repo}/commits/<triage_sha>/check-runs` and `/repos/{owner}/{repo}/check-runs/{check_run_id}/annotations`.
- 2026-09-30T23:37-0700 Gated to check-runs reporting `annotations_count > 0` to minimize unnecessary API round trips.
- 2026-09-30T23:37-0700 Annotations rendered with format `ANNOTATION [<level>] <path>:<line> by <check_suite_name>:\n<message>\n` to mirror the existing `DIFF`, `REVIEW`, and `ISSUE` diagnostic formats.
- 2026-09-30T23:37-0700 Verification suite updated in `tests/verify-install.sh` for API query count and scratch redirect count (3 to 5).
- 2026-10-01T07:18-0700 Check-run annotations filter reads from `.output.annotations_count` with fallback to `.annotations_count`; GitHub Checks API nests `annotations_count` under `output`, so top-level lookup was evaluating to null and dropping all check runs.
- 2026-10-14 Stacked review loop hardens the fetch: both endpoints paginate, every page is shape-validated, fetched counts reconcile against `annotations_count` with a warning on mismatch, every failure is an ERROR plus exit 1, and the head drift re-check runs after the annotation loop.

## What Changed

- `skills/agent-review-pr-comments/SKILL.md`:
  - Updated frontmatter description and introductory overview to include check-run annotations.
  - Updated prerequisites to note that Section 1A resolves `<pr_number>` and `<triage_sha>`.
  - Added check-run query and annotation extraction in Section 1A bash snippet.
  - Updated Section 1B triage instructions to cover check-run annotations.
  - 2026-10-01T07:18-0700 Updated Section 1A jq check-runs selector to check `.output.annotations_count`.
- `tests/verify-install.sh`:
  - Updated `pr url quoted: prc` assertion from 3 to 5.
  - Updated `scratch redirects guarded: prc` assertion from 3 to 5.
  - 2026-10-01T07:18-0700 Added section 18 asserting `.output.annotations_count` and testing filter against sample check runs.
  - 2026-10-14 Rewrote the annotation block (`$triage_sha` interpolation, `jq -sr` TSV selection read in the current shell, numeric id guard, annotations count printed, drift re-check last); suite pins updated (5 paginated fetches, 6 guarded scratch redirects) and section 18 executes match, drift, and failure legs against stubs.
- 2026-10-01T07:18-0700 `~/.agents/review-refinements.md`:
  - Added `Nested Payload Path Fidelity` under Pillar 5.

## Verification

- `./tests/verify-install.sh`: passed with 0 failures.
- Checked ASCII compliance: pure ASCII, zero em dashes.
- `./install.sh --all --no-refinements`: installed across `~/.agents`, `~/.config/muse`, `~/.claude`, `~/.codex`, and `~/.gemini`.
- PR opened: https://github.com/hyeons-lab/agent-review-loop/pull/7.

## Commits

- feat(skills): add check-run annotations to agent-review-pr-comments
- docs(devlog): record PR 7 submission and local skill reinstallation
- fix(skills): read check-run annotations count from output
- fix(skills): harden annotation fetching (stacked review loop)

