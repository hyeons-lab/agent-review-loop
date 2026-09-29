# 000004: agent-review-check-ci skill

Date: 2026-09-29
Branch: feat/agent-review-check-ci
PR: https://github.com/hyeons-lab/agent-review-loop/pull/6 (open, in progress)

## Intent

Add a fourth skill, `agent-review-check-ci`, alongside the existing
three. It checks CI status on a target PR, diagnoses and fixes red
builds (build breaks, test failures, lint, flakes, infra), and folds
CI-caught misses into the shared cross-agent review pillars, mirroring
the pr-comments structure.

## Design

- Skill shape mirrors `agent-review-pr-comments`: resolve plus run-root
  bootstrap span (section 1A), failure triage by class (1B),
  diagnose-fix-validate loop (2), thematic synthesis protocol (3),
  commit/push/CI management (4), persisted summary (5).
- 9 fenced bash blocks (1A, logs/rerun, backup, commit, stack push,
  plain push, cancel runs, poll, run list), all `bash -n` clean with
  quoted placeholders.
- 4 single-quoted paste sites with escape notes (pr input, git add,
  push refspec, cd re-derive), matching house style (1-backslash idiom).
- 8th mirror span: `check-ci` reaper/rounds tokens, drift-identical
  post-normalization; all spans plus comments updated 7 to 8.
- No review-thread resolving (no comment threads in scope); single-shot
  chmod arm keeps the no-cleanup shape (EXIT trap covers it).

## Suite integration

- `install.sh` and suite `SKILLS` extended; `skill_files` arm extended.
- `normalize.sed`: 4 check-ci mappings; forbid alternations extended.
- Static pins mirrored from prc (echoes, trap, chmod, rounds, notes,
  unsets, quoting, redirects, fence range, resolve range, order).
- Compact live-fire trio (success path: keeps rounds, removes scratch,
  restores prior trap, stdout contract, re-attach).
- File-count pins 35 to 45; span-count pins 7 to 8; regen waypoint loop
  covers all 4 skills (8 waypoints).

## Verification

- `./tests/verify-install.sh`: 1096 passed, 0 failed (baseline and
  varied-alphabet hostile TMPDIR identically); shellcheck and ASCII
  gates clean.
- Golden regenerated via `--regen-golden` (exactly the 7 to 8 line).

## Check-CI cycle 1 on PR #6 (2026-09-29)

- CI state: no red checks. Only check is external `[code]smith`
  (bucket skipping, state SKIPPED); branch run list shows Copilot
  code review completed success at the triage SHA. Repo has no
  `.github/workflows`, so no Actions legs exist to fail.
- Copilot left a COMMENTED review (not requesting changes);
  comment triage belongs to `agent-review-pr-comments`, out of scope.
- First live run caught a defect in the skill's own section 1A:
  `gh pr checks --json name,bucket,workflowName` is rejected by gh
  2.95.0 (`Unknown JSON field: "workflowName"`; the field is
  `workflow`), failing the whole snapshot fetch. Fixed lines 175-176
  (`workflowName` to `workflow` in both the `--json` list and the jq
  selector); no other skill or test references the wrong name.
- Verification: fixed lines run verbatim (rc 0); suite still 1096
  passed, 0 failed; lesson merged into canonical Pillar 1
  (Installed Binary Grammar Verification).
