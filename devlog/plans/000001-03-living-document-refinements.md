# Plan: Living Document Protocol for Review Refinements

## Thinking

The user requested that when adding bullets to `review-refinements.md`, all suggestions from the review should be added, but existing bullets should also be rewritten to be more general so they incorporate the new suggestions, making `review-refinements.md` a living document.

Previously, the refinement protocol contained a mechanical cap ("at most 2 new or refined bullets per round, at most 5 per loop run"). This caused review agents to discard valid findings or decline to update the refinements file even when meaningful improvements were uncovered. Additionally, the guidance emphasized passive subsumption rather than active synthesis, leading to either arbitrary dropping of lessons or accumulation of point-specific rules.

Treating `review-refinements.md` as a living document requires two structural shifts:

1. **Incorporate all suggestions without arbitrary quotas**: Every durable suggestion and lesson uncovered during review or PR triage must be incorporated into the refinements store.
2. **Active generalization and synthesis**: When new suggestions arise under a pillar, the agent inspects the existing bullets in that pillar and actively rewrites them into broader, higher-level principles that integrate both the prior knowledge and the new lessons. If a suggestion introduces a completely distinct concern within the pillar, it is added as a new bullet, also written at a general cross-stack level.

This philosophy needs to be codified across the three skills (`agent-review-loop`, `agent-review-report`, `address-pr-comments`), `thematic-review-pillars.md`, `templates/review-refinements.template.md`, `README.md`, and the active `~/.agents/review-refinements.md` store.

## Plan

1. **Update `templates/review-refinements.template.md`**:
   - Update header rules: remove artificial quotas and define the living document synthesis model (incorporate all suggestions, rewrite bullets to be broader and more general).
   - Refine the 8 starter bullets across pillars to demonstrate living document generalization.
2. **Update `~/.agents/review-refinements.md`**:
   - Align header instructions with the living document protocol.
   - Synthesize and rewrite the bullets across the 8 pillars, integrating recent review findings into generalized, living principles.
3. **Update `skills/agent-review-loop/SKILL.md`**:
   - Update Section 6 ("How to Update the Refinements File Correctly"), replacing the 2-bullet ceiling with the living document requirement to incorporate all suggestions through active generalization and rewriting.
4. **Update `skills/agent-review-report/SKILL.md`**:
   - Synchronize Section 7 with the living document update protocol.
5. **Update `skills/address-pr-comments/SKILL.md`**:
   - Synchronize Section 3 with the living document update protocol.
6. **Update `skills/agent-review-loop/thematic-review-pillars.md` & `README.md`**:
   - Align refinement file descriptions with the living document model.
7. **Verification**:
   - Run `./tests/verify-install.sh` to confirm syntax, idempotency, and non-vacuous assertions pass cleanly.
   - Confirm zero em dashes (U+2014) across all touched files.
   - Run `./install.sh && ./install.sh --upgrade` to synchronize installed skills.
8. **Documentation & Devlog**:
   - Record decisions and changes in `devlog/000001-feat-generalize-review-criteria.md`.

### Evolution: Add/Merge with Total Bullet Cleanup

Per user guidance, agents must not simply keep appending new bullets without cleaning up the total bullets. The protocol explicitly requires:
- **Add or merge**: For each actionable suggestion, decide whether to merge it into an existing bullet (broadening and rewriting it) or add it as a new bullet if truly distinct.
- **Clean up total bullets**: After adding or merging, review all bullets under that pillar as a whole. Clean them up, reorganize them for clarity, consolidate overlapping themes, and eliminate redundancies.
- **Evolve over time**: The document evolves through this active curation, remaining tightly organized and high-signal instead of accumulating an unbounded list of uncurated bullets.
