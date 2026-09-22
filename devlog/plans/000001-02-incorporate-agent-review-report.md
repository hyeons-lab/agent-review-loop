# Plan: Incorporate agent-review-report Skill

## Thinking

Branch `feat/per-round-learnings-and-upgrade` had local changes defining a third skill, `agent-review-report`, a report-only max-effort review that presents findings to the user and posts to a PR only with explicit user approval.

These changes need to be incorporated into PR 2 (`feat/generalize-review-criteria`) while aligning with the PR 2 architecture:
1. `skills/agent-review-report/SKILL.md` must use the 8 canonical software engineering review pillars adopted in PR 2 rather than legacy systems/inference categories.
2. The resolution order in `agent-review-report/SKILL.md` must include the `REVIEW_REFINEMENTS_LEGACY=1` opt-in rule and the standing rule for cross-stack bullet generality.
3. Subagent timeout handling and platform-specific execution details must be synchronized with `skills/agent-review-loop/SKILL.md`.
4. Installer (`install.sh`), test suite (`tests/verify-install.sh`), and documentation (`README.md`) must support all three skills (`agent-review-loop`, `agent-review-report`, and `address-pr-comments`).
5. All verification tests must pass, and the entire repository must remain free of em dashes and AI attribution.

## Plan

1. Create `skills/agent-review-report/agents/openai.yaml` with Codex display metadata.
2. Create `skills/agent-review-report/SKILL.md` adapted to canonical software engineering pillars and legacy opt-in semantics.
3. Update `install.sh` to include `agent-review-report` in `SKILLS` and `skill_files`.
4. Update `tests/verify-install.sh` to assert `agent-review-report` across all test suites.
5. Update `README.md` to document the three skills, installation options, invocation commands, and manual install steps.
6. Synchronize cross-skill references in `skills/address-pr-comments/SKILL.md`, `skills/agent-review-loop/SKILL.md`, and `skills/agent-review-loop/thematic-review-pillars.md`.
7. Execute `./tests/verify-install.sh` and ensure zero failures and zero em dashes.
8. Update devlogs and prepare changes for commit.
