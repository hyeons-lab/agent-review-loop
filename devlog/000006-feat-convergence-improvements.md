# feat/convergence-improvements

## Agent

Claude Code (claude-sonnet-5-5) @ agent-review-loop branch feat/convergence-improvements

## Intent

Make `agent-review-loop` converge faster: fewer repeated rounds, fewer defects introduced by fix commits, and a defensible stop signal. Derived from an 8 round run over a 20 PR stack where full-round finding counts stayed at 50 to 90. Plan: `devlog/plans/000006-01-convergence-improvements.md`.

## Progress

- [x] Plan and devlog
- [ ] 1 convergence phase and severity gate
- [ ] 2 provenance labels and the new-class stop rule
- [ ] 3 executable evidence and the tooling ladder
- [ ] 4 fix-check regression hunter and fixer class sweep
- [ ] 5 cross-scope class sweep
- [ ] 6 coverage ledger and sharding
- [ ] 7 redundancy and capture-recapture estimate
- [ ] 8 effort routing
- [ ] 9 mirrors, tests, docs, dogfood

## What Changed

2026-10-15T19:41-0700 devlog/plans/000006-01-convergence-improvements.md, devlog/000006-feat-convergence-improvements.md: plan and devlog.

## Decisions

2026-10-15T19:41-0700 Branch from origin/main in a worktree; the main checkout has unrelated untracked devlog files from earlier work that this branch does not touch.
2026-10-15T19:41-0700 Number the devlog 000006 (highest on main is 000005); renumber on merge conflict.

## Commits

HEAD: docs: plan the convergence improvements for agent-review-loop
