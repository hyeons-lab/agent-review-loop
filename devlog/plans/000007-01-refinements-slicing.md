# Plan 000007-01: Slice learnings by pillar, cap bullet length

## Problem

Every reviewer reads every shared learnings file whole. The canonical file
is about 477k characters (about 119k tokens), so one max round pays that
payload nine times before any diff tokens. Rounds, not depth, dominate
token cost: a max round fields about 4.5 times the agents of a medium
round, so uniform max only wins when it cuts rounds by more than that.

## Changes

1. Slice learnings by pillar before spawning: per-pillar slice files under
   the run scratch directory plus a titles index (headings and bullet
   titles, no bodies). Each reviewer gets only its own pillars' slices
   plus the index. Synthesis reads sections on demand by heading. Files
   without canonical headings are handed whole, with the fallback stated.
2. Bullet budget: new and edited bullets stay at or under 600 characters
   (one trigger, one hazard, one fix shape, one verification). Longer
   lessons split or merge broader. While editing a pillar, tighten any
   bullet over budget in that pillar.
3. Compress the canonical file's longest bullets (over 1200 characters)
   in place, preserving titles, triggers, hazards, fix shapes, and
   verifications. Headings and bullet count must stay identical.
4. Pin the slicing phrases and the budget in tests/verify-install.sh, in
   the loop and report skills, the pillars file, and the pr-comments and
   check-ci filing steps. Document the mechanism in README.

## Expected effect

A one-pillar reviewer reads about 6k to 36k learnings tokens instead of
about 119k. A two-pillar reviewer at high reads roughly a quarter of the
old payload. Remaining over-budget bullets (multi-lesson bundles, worst
about 2k characters) split in later cycles under the new budget rule.
