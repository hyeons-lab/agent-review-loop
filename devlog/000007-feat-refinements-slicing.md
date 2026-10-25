# feat/refinements-slicing

## Intent

Cut review token cost: reviewers read only their own pillars' learnings
instead of every learnings file whole, new bullets are capped at 600
characters, and the canonical refinements file's longest bullets are
compressed. Plan: `devlog/plans/000007-01-refinements-slicing.md`.
Stacked on `feat/convergence-improvements` (PR #10).

## Progress

- [x] Plan and devlog
- [x] Failing pins first (12 new checks red on the untouched skills)
- [x] Slicing rule in pillars, loop, and report; budget in all four skills
- [x] README mechanism bullet
- [x] Canonical compression with backup and invariant verification
- [x] Full suite green

## What Changed

2026-10-24T11:25-0700 tests/verify-install.sh: 12 pins for own-pillar
slices, the titles index, the removed whole-file instruction, and the
600 character budget across pillars, loop, report, pr-comments, and
check-ci. Observed failing first: 1335 passed, 12 failed.
2026-10-24T11:25-0700 skills/agent-review-loop/thematic-review-pillars.md:
slicing rule (per-pillar slices plus titles index, synthesis on demand,
whole-file fallback stated) and the bullet budget in the protocol.
2026-10-24T11:25-0700 skills/agent-review-loop/SKILL.md and
skills/agent-review-report/SKILL.md: reviewer prompts hand own-pillar
slices plus the titles index; criteria sections point at the slicing
rule; filing steps carry the budget.
2026-10-24T11:25-0700 skills/agent-review-pr-comments/SKILL.md and
skills/agent-review-check-ci/SKILL.md: filing steps carry the budget.
2026-10-24T11:25-0700 README.md: sliced learnings bullet under
Converging faster.
2026-10-24T11:25-0700 Canonical ~/.agents/review-refinements.md (outside
the repo, not committed): backup snapshot
review-refinements-20261024-112328-51631-q48fui.md, then the 34 bullets
over 1200 characters compressed in place. File: 494,528 to 477,461
characters. Verified: 8 pillar headings byte-identical, 771 bullets
before and after, every bullet title unchanged, zero em dashes, exactly
34 lines changed.

## Decisions

2026-10-24T11:25-0700 Stacked worktree on feat/convergence-improvements:
the slicing text amends its lens, shard, and synthesis contract.
2026-10-24T11:25-0700 Slicing, not compression, is the multiplier: a
one-pillar slice is about 6k to 36k tokens against about 119k for the
whole file. Compression of the longest tail alone saved 3.5 percent.
2026-10-24T11:25-0700 Over-budget survivors (multi-lesson bundles, worst
about 2k characters) were tightened, not split, to keep bullet titles
and counts stable this cycle. The 600 character budget plus the
tighten-while-editing rule splits them in later cycles.
2026-10-24T11:25-0700 Backups under ~/.agents/backups now exceed five.
Nothing was pruned; pruning needs explicit user confirmation.

## Commits

HEAD: feat(skills): slice learnings by pillar and cap bullet length
