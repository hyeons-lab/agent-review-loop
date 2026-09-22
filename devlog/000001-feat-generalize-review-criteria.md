# 000001-feat-generalize-review-criteria.md

**Agent:** Antigravity (Gemini 3.8 Flash) @ repository branch feat/generalize-review-criteria  
**Intent:** Generalize review criteria and pillars for any repository, make legacy refinements opt-in via REVIEW_REFINEMENTS_LEGACY=1, enforce repo-local placement for stack-specific lessons, and seed canonical refinements with general cross-stack bullets.

## Decisions

- 2026-09-21T17:08-07:00 Preserve 8 pillar headings byte-for-byte: The titles `### Pillar 1:` through `### Pillar 8:` form a frozen contract across review loops and must remain untouched.
- 2026-09-21T17:08-07:00 Make legacy refinements opt-in via REVIEW_REFINEMENTS_LEGACY=1: The 322-line legacy file contains project-specific Rust/GPU/inference bullets that add noise to non-inference projects; default to skipping it unless explicitly requested.
- 2026-09-21T17:08-07:00 Seed 8 domain-neutral bullets in canonical refinements: Populate one high-signal, stack-agnostic principle per pillar in `~/.agents/review-refinements.md` and the starter template, keeping the existing Pillar 6 license attribution bullet intact.
- 2026-09-21T17:37-07:00 Adopt canonical software engineering review pillars: Completely replace legacy systems/inference pillar categories with 8 universal software engineering pillars (Correctness, Security, Concurrency, Error Handling, API Design, Performance, Simplicity, Testing/Observability).
- 2026-09-21T17:46-07:00 Align agent-review-report with canonical SWE pillars: Harmonized the incorporated report skill with the 8 canonical software engineering review pillars and legacy opt-in semantics.

## What Changed

- 2026-09-21T17:08-07:00 `devlog/plans/000001-01-generalize-review-criteria.md`: Initial implementation plan for generalizing review criteria.
- 2026-09-21T17:11-07:00 `skills/agent-review-loop/thematic-review-pillars.md`: Rewrote base pillar bullets domain-neutral using trigger/hazard/fix-shape structure, demoting systems cases to parenthetical examples; preserved 8 pillar headings byte-for-byte; updated resolution order and added standing generality rule.
- 2026-09-21T17:11-07:00 `skills/agent-review-loop/SKILL.md`: Updated resolution order with REVIEW_REFINEMENTS_LEGACY=1 opt-in and prioritized repo-local over canonical; strengthened write target rules with the standing cross-stack generality requirement.
- 2026-09-21T17:11-07:00 `skills/address-pr-comments/SKILL.md`: Aligned resolution order and write target rules with REVIEW_REFINEMENTS_LEGACY=1 and the standing generality requirement.
- 2026-09-21T17:11-07:00 `README.md`: Documented REVIEW_REFINEMENTS_LEGACY=1, repo-local vs canonical refinements placement, and the standing rule for cross-stack bullet generality.
- 2026-09-21T17:11-07:00 `install.sh`: Updated legacy refinements note on seed to inform users that REVIEW_REFINEMENTS_LEGACY=1 is needed to include legacy files in reviews.
- 2026-09-21T17:11-07:00 `tests/verify-install.sh`: Added test assertion verifying REVIEW_REFINEMENTS_LEGACY=1 is mentioned in the legacy install note.
- 2026-09-21T17:11-07:00 `templates/review-refinements.template.md`: Added 8 domain-neutral seed bullets (one per pillar) and updated writer rules with the standing generality rule.
- 2026-09-21T17:37-07:00 `skills/agent-review-loop/thematic-review-pillars.md`: Replaced systems/inference pillar categories with 8 canonical software engineering review pillars.
- 2026-09-21T17:37-07:00 `skills/agent-review-loop/SKILL.md`: Updated reviewer pillar list to match the 8 canonical software engineering pillars.
- 2026-09-21T17:37-07:00 `README.md`: Updated pillar descriptions to reference the canonical software engineering pillars.
- 2026-09-21T17:37-07:00 `templates/review-refinements.template.md`: Updated template headers and starter bullets to canonical software engineering pillars.
- 2026-09-21T17:37-07:00 `devlog/plans/000001-01-generalize-review-criteria.md`: Appended note on transition to canonical SWE pillars.
- 2026-09-21T17:46-07:00 `devlog/plans/000001-02-incorporate-agent-review-report.md`: Plan for incorporating agent-review-report skill into PR 2.
- 2026-09-21T17:46-07:00 `skills/agent-review-report/agents/openai.yaml`: Added Codex metadata for agent-review-report skill.
- 2026-09-21T17:46-07:00 `skills/agent-review-report/SKILL.md`: Added agent-review-report skill definition adapted to canonical SWE review pillars and REVIEW_REFINEMENTS_LEGACY=1 opt-in.
- 2026-09-21T17:46-07:00 `install.sh`: Added agent-review-report to SKILLS, skill_files, and completion message.
- 2026-09-21T17:46-07:00 `tests/verify-install.sh`: Added agent-review-report to verification suite across all test sections.
- 2026-09-21T17:46-07:00 `README.md`: Updated description, contents, install tables, uninstall paths, and manual install steps for 3 skills.
- 2026-09-21T17:46-07:00 `skills/address-pr-comments/SKILL.md`: Updated cross-skill refinements reference.
- 2026-09-21T17:46-07:00 `skills/agent-review-loop/SKILL.md`: Added mirroring sync note with agent-review-report.
- 2026-09-21T17:46-07:00 `skills/agent-review-loop/thematic-review-pillars.md`: Updated skill name list in document header.

## Issues

## Commits

- c897bc9: feat: generalize review criteria across repositories and stacks
- cddbd79: refactor: adopt canonical software engineering review pillars
- HEAD: feat: incorporate agent-review-report skill
