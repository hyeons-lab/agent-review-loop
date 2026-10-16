# feat/convergence-improvements

## Agent

Claude Code (claude-sonnet-5-5) @ agent-review-loop branch feat/convergence-improvements

## Intent

Make `agent-review-loop` converge faster: fewer repeated rounds, fewer defects introduced by fix commits, and a defensible stop signal. Derived from an 8 round run over a 20 PR stack where full-round finding counts stayed at 50 to 90. Plan: `devlog/plans/000006-01-convergence-improvements.md`.

## Progress

- [x] Plan and devlog
- [x] 1 convergence phase and severity gate
- [x] 2 provenance labels and the new-class stop rule
- [x] 3 executable evidence and the tooling ladder
- [x] 4 fix-check regression hunter and fixer class sweep
- [x] 5 cross-scope class sweep
- [ ] 6 coverage ledger and sharding
- [ ] 7 redundancy and capture-recapture estimate
- [ ] 8 effort routing
- [ ] 9 mirrors, tests, docs, dogfood

## What Changed

2026-10-15T19:41-0700 devlog/plans/000006-01-convergence-improvements.md, devlog/000006-feat-convergence-improvements.md: plan and devlog.
2026-10-15T19:43-0700 skills/agent-review-loop/SKILL.md: convergence phase and severity gate (section 2 subsection; step 2 Backlog Only class; step 3 gate-severity scope; step 6 Backlog line; finishing-up backlog disposition; commit invariant).
2026-10-15T19:44-0700 skills/agent-review-loop/SKILL.md: finding provenance labels (class, origin, newClass), run class ledger, plateau rule, reviewer-prompt bullet, step 6 Provenance line, step 2 plateau handling.
2026-10-15T19:45-0700 skills/agent-review-loop/SKILL.md: tooling ladder (per-language deep tools, detect-never-install, tools.md), evidence types ran/trace/read, unreproduced-findings rule, Tool evidence reviewer bullet, step 6 Unreproduced line.
2026-10-15T19:46-0700 skills/agent-review-loop/SKILL.md: fixer self-critique (class sweep, failure-path review, contract check, hostile read) in step 3; fix-check regression-hunter duties (own class sweep, adversarial probes, what-could-go-wrong list) in step 4.
2026-10-15T19:47-0700 skills/agent-review-loop/SKILL.md: step 2b class sweep across scopes (derive sweep from each gate-severity class, run over every scope, sweeps.md, recurrence findings tagged sweep), step 2 Actionable pointer, step 6 Sweeps line.

## Decisions

2026-10-15T19:41-0700 Branch from origin/main in a worktree; the main checkout has unrelated untracked devlog files from earlier work that this branch does not touch.
2026-10-15T19:41-0700 Number the devlog 000006 (highest on main is 000005); renumber on merge conflict.
2026-10-15T19:43-0700 Quality and nitpick findings are backlogged during convergence and applied once in a polish pass, because fix churn on low-severity items was feeding new correctness findings. `all-severities` keeps the old behavior.
2026-10-15T19:44-0700 Plateau means two consecutive full rounds with no fix-induced finding and no new gate-severity class. It asks the user to choose and never finishes the loop or reports a clean review on its own.
2026-10-15T19:45-0700 Gate-severity findings need a probe or an explicit trace; read-only claims are held as unreproduced and promoted on reproduction, a second independent report, or user acceptance. Deeper tools run once per round and feed reviewers evidence.
2026-10-15T19:46-0700 A fix that cures one instance and leaves siblings, or breaks on cancel, repeat, empty or maximum input, is the main source of next-round findings. Fixers must sweep and self-review; the fix check now actively tries to break each fix and counts missed siblings as regressions.
2026-10-15T19:47-0700 A class found in one place is searched for everywhere in the same round, before fixes: the whole repo for a single-diff run, every scope for a multi-scope run. Hits become recurrence findings in their owning scope.

## Commits

42eea9f: docs: plan the convergence improvements for agent-review-loop
3f6a130: feat(skills): add convergence phase and severity gate to agent-review-loop
6eede5b: feat(skills): add finding provenance labels and the plateau rule
2710714: feat(skills): add the tooling ladder and executable-evidence rule
6583043: feat(skills): add fixer self-critique and a regression-hunting fix check
HEAD: feat(skills): sweep each found defect class across every scope
