# 000002-02-scoped-rereview-confirmation.md

## Thinking

Every loop round currently reruns the full fan-out at fixed effort even
when only one lens found issues, so quiet lenses burn reviewer budget
re-reading a diff they already cleared. The fix is to narrow post-fix
rounds to dirty lenses: lenses with at least one actionable finding are
the only ones with open questions.

The risk is cross-pillar fallout: a fix for one pillar can move a problem
into another (a contract change breaks callers, an error mapping change
hides failures), and sitting-out lenses would never see it. The mitigation
is a full confirmation round: once narrowed rounds go clean, run every
lens once at the loop's effort before finishing. When confirmation finds
actionable items, resume narrowing on the new dirty set. A round that runs
every lens counts as full even when every lens was dirty, which avoids a
redundant confirmation after an all-dirty round.

Dirty tracking is by lens, not by pillar, because findings carry
file:line, not pillar tags. The mapping is exact at `max` (one reviewer
per pillar), paired at `high`, halved at `medium`, and degenerate at
`low` (the single lens reruns whenever it found anything actionable).
Reviewers stay scoped to their own pillars but may flag a severe hazard
clearly owned by a sitting-out lens in one line, so that lens rejoins the
dirty set next round instead of waiting for confirmation. The 10 round cap
counts subset and confirmation rounds together. The quiet-round step-down
keeps counting all rounds unchanged.

## Plan

1. Section 2: restate the fixed-effort rule as fixed depth per pillar and
   fixed full-round fan-out, with coverage narrowing between rounds and
   one full confirmation round closing the loop.
2. Intro paragraph: scoped re-review plus confirmation wording.
3. Step 1: add a lens scoping paragraph (round 1 and confirmations run
   every lens; other rounds rerun dirty lenses only; synthesis covers
   running lenses only) and a round-scope reviewer bullet including the
   one-line out-of-scope flag.
4. Step 2: split the stop condition three ways. Actionable: fix path as
   today, next round narrows. Clean or nitpicks-only after a subset
   round: run one full confirmation round next. Clean or nitpicks-only
   after a full round: finish path as today.
5. Step 6: round summary gains a scope-next line (dirty lenses rerunning,
   lenses sitting out, confirmation owed, or done).
6. Step 7: dirty-set carryover (actionable lenses plus out-of-scope
   flags), full-round definition, and cap counting.
7. README: one clause noting scoped re-review plus confirmation.
8. Verify: em dash grep over the worktree bundle, `./tests/verify-install.sh`
   from the worktree, and a full read of the loop skill for consistency.
