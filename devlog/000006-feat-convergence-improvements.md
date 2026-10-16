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
- [x] 6 coverage ledger and sharding
- [x] 7 redundancy and capture-recapture estimate
- [x] 8 effort routing
- [x] 9 mirrors, tests, docs, dogfood

## What Changed

2026-10-15T19:41-0700 devlog/plans/000006-01-convergence-improvements.md, devlog/000006-feat-convergence-improvements.md: plan and devlog.
2026-10-15T19:43-0700 skills/agent-review-loop/SKILL.md: convergence phase and severity gate (section 2 subsection; step 2 Backlog Only class; step 3 gate-severity scope; step 6 Backlog line; finishing-up backlog disposition; commit invariant).
2026-10-15T19:44-0700 skills/agent-review-loop/SKILL.md: finding provenance labels (class, origin, newClass), run class ledger, plateau rule, reviewer-prompt bullet, step 6 Provenance line, step 2 plateau handling.
2026-10-15T19:45-0700 skills/agent-review-loop/SKILL.md: tooling ladder (per-language deep tools, detect-never-install, tools.md), evidence types ran/trace/read, unreproduced-findings rule, Tool evidence reviewer bullet, step 6 Unreproduced line.
2026-10-15T19:46-0700 skills/agent-review-loop/SKILL.md: fixer self-critique (class sweep, failure-path review, contract check, hostile read) in step 3; fix-check regression-hunter duties (own class sweep, adversarial probes, what-could-go-wrong list) in step 4.
2026-10-15T19:47-0700 skills/agent-review-loop/SKILL.md: step 2b class sweep across scopes (derive sweep from each gate-severity class, run over every scope, sweeps.md, recurrence findings tagged sweep), step 2 Actionable pointer, step 6 Sweeps line.
2026-10-15T19:48-0700 skills/agent-review-loop/SKILL.md: coverage ledger (coverage.tsv, READ lines, hash invalidation), coverage debt, sharding above 1200 lines or 12 files, 24-reviewer budget with debt rotation, finish only with zero debt, Coverage entry ledger summary.
2026-10-15T19:50-0700 skills/agent-review-loop/SKILL.md: redundancy (verification twin by default, redundancy 2 optional), independence rules, Chapman residual estimate, use in stop proposals, step 2 twin gate, step 6 Redundancy line.
2026-10-15T19:50-0700 skills/agent-review-loop/SKILL.md: per-scope effort routing (floor stays the chosen effort; scopes routed to max by user hot list, size over 1500 lines, fix-induced churn, risky areas), Section 2 fixed-effort wording, step 6 Routing line.
2026-10-15T19:54-0700 skills/agent-review-report/SKILL.md (evidence types, class label, tool evidence mirrored; mirror comments updated in both skills), tests/verify-install.sh (25 convergence pins, mutation-checked), README.md (new arguments and Converging faster section).
2026-10-15T19:59-0700 skills/agent-review-loop/SKILL.md, skills/agent-review-report/SKILL.md, tests/verify-install.sh: fixes from an independent consistency review of steps 1 to 9 (zero-debt rule measured at round end, clean reports carry READ lines, 24 is a concurrency limit with final and twin sets never rotating, estimate only under redundancy 2, twin skipped without isolation, polish at most once, plateau needs a gate finding and ignores subset rounds, backlog never dirties lenses or breaks the streak, unreproduced-only rounds are Backlog Only, sweep hits inherit the spawning lens, finding format carries class/origin/evidence, ladder runs after run setup, new lines persisted, routing.md, origin precedence, intro wording, commit invariant names plateau finish); 13 new pins.

## Decisions

2026-10-15T19:41-0700 Branch from origin/main in a worktree; the main checkout has unrelated untracked devlog files from earlier work that this branch does not touch.
2026-10-15T19:41-0700 Number the devlog 000006 (highest on main is 000005); renumber on merge conflict.
2026-10-15T19:43-0700 Quality and nitpick findings are backlogged during convergence and applied once in a polish pass, because fix churn on low-severity items was feeding new correctness findings. `all-severities` keeps the old behavior.
2026-10-15T19:44-0700 Plateau means two consecutive full rounds with no fix-induced finding and no new gate-severity class. It asks the user to choose and never finishes the loop or reports a clean review on its own.
2026-10-15T19:45-0700 Gate-severity findings need a probe or an explicit trace; read-only claims are held as unreproduced and promoted on reproduction, a second independent report, or user acceptance. Deeper tools run once per round and feed reviewers evidence.
2026-10-15T19:46-0700 A fix that cures one instance and leaves siblings, or breaks on cancel, repeat, empty or maximum input, is the main source of next-round findings. Fixers must sweep and self-review; the fix check now actively tries to break each fix and counts missed siblings as regressions.
2026-10-15T19:47-0700 A class found in one place is searched for everywhere in the same round, before fixes: the whole repo for a single-diff run, every scope for a multi-scope run. Hits become recurrence findings in their owning scope.
2026-10-15T19:48-0700 Reviewers report the ranges they read; the ledger invalidates a range when its text changes; large diffs shard by module and the next round prioritizes unread or changed code. A loop may finish only after a full round over every shard with zero coverage debt.
2026-10-15T19:50-0700 A loop finishes only when two independent reviewer sets agree. The overlap between the sets gives a Chapman estimate of how many gate-severity defects remain, reported as a lower bound and used to inform, never to end, the loop.
2026-10-15T19:50-0700 Effort stays the floor for every scope; hot, very large, high-churn or high-risk scopes are raised to max. Routing only raises, and a promoted scope restarts its lens partition with a full round.
2026-10-15T19:54-0700 Mutation check: removing a heading and the Chapman formula each failed a pin, then the file was restored. Suite: 1322 passed.
2026-10-15T19:59-0700 An independent read of the finished skill found 16 defects in the spec (unreachable finish rule, a Chapman estimate that was always zero in default mode, a clean reviewer unable to emit coverage lines, polish and confirmation able to loop to the cap, and others). All 16 are fixed, 13 pins added; the review hand-back was verified against the cited lines before applying.

## Commits

42eea9f: docs: plan the convergence improvements for agent-review-loop
3f6a130: feat(skills): add convergence phase and severity gate to agent-review-loop
6eede5b: feat(skills): add finding provenance labels and the plateau rule
2710714: feat(skills): add the tooling ladder and executable-evidence rule
6583043: feat(skills): add fixer self-critique and a regression-hunting fix check
f79086a: feat(skills): sweep each found defect class across every scope
0cbdf4d: feat(skills): add a coverage ledger and diff sharding
fafb023: feat(skills): add independent twin reviewers and a residual-defect estimate
581aaa1: feat(skills): route risky or large scopes to max effort
fcce433: docs(skills): mirror convergence rules, pin them in tests, document them
HEAD: fix(skills): resolve contradictions found by the consistency review
