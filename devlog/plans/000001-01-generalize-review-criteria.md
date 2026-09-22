# Generalize Review Criteria

## Thinking

The review loop is designed to be universal across any programming language, stack, and repository. However, the initial base pillars in `skills/agent-review-loop/thematic-review-pillars.md` were heavily influenced by systems programming and inference engines (e.g., mmap, GGUF, SIMD, FFI/WASM). Furthermore, the legacy refinements file at `~/.gemini/review-refinements.md` contains 322 lines and nearly 300 bullets exclusively derived from a single Rust local-inference project.

When `agent-review-loop` or `address-pr-comments` executes in an arbitrary project (such as a TypeScript web app, a Python data pipeline, or a Go microservice), loading hundreds of inference-specific bullets pollutes reviewer context, burns tokens, and causes reviewers to flag irrelevant low-level invariants.

To solve this:
1. The base pillar bullets in `skills/agent-review-loop/thematic-review-pillars.md` must be rewritten into domain-neutral trigger, hazard, and fix-shape language. Specific low-level systems cases (mmap, SIMD, GGUF, FFI/WASM) must be demoted to parenthetical examples rather than the primary criteria.
2. The 8 `### Pillar N:` titles must remain strictly byte-identical to maintain frozen cross-loop contract compatibility.
3. The legacy file `~/.gemini/review-refinements.md` must become opt-in: loops read it only when `REVIEW_REFINEMENTS_LEGACY=1` is set in the environment; otherwise it is skipped.
4. The write rules across all documentation and skills must be strengthened: any lesson mentioning repo-specific modules, crates, internal APIs, or stack specifics must be filed in the repo-local `.agents/review-refinements.md`. Only stack-agnostic principles that can help a review in a completely different repo on a completely different stack belong in canonical `~/.agents/review-refinements.md`.
5. Canonical `~/.agents/review-refinements.md` should be seeded with one tight, high-signal general bullet per pillar (8 total).
6. The installer (`install.sh`) and tests (`tests/verify-install.sh`) must reflect this opt-in behavior and ensure zero em dashes across all prose.

## Plan

1. **Plan & Devlog setup**:
   - Establish `devlog/000001-feat-generalize-review-criteria.md` and this plan file.

2. **Rewrite base pillar bullets in `thematic-review-pillars.md`**:
   - Keep the 8 `### Pillar N:` headings byte-identical.
   - For each pillar, rewrite the bullets to express universal software engineering invariants (resource safety, lifecycle management, error propagation, interface portability, numeric bounds, contract integrity, performance efficiency, code simplicity). Demote systems/inference cases to brief parenthetical examples.
   - Update the two-tier architecture section to define the `REVIEW_REFINEMENTS_LEGACY=1` opt-in rule and the standing rule for generality.

3. **Update skill definitions and documentation**:
   - Update `skills/agent-review-loop/SKILL.md`: resolution order (making legacy opt-in via `REVIEW_REFINEMENTS_LEGACY=1`), and write target rules (standing rule for stack generality).
   - Update `skills/address-pr-comments/SKILL.md`: resolution order and write target rules to match.
   - Update `README.md`: document `REVIEW_REFINEMENTS_LEGACY=1`, repo-local placement for repo-specific lessons, and the generality rule.

4. **Update installer and tests**:
   - In `install.sh`, update the legacy note when `~/.gemini/review-refinements.md` is detected to explain that it is preserved and can be enabled via `REVIEW_REFINEMENTS_LEGACY=1`.
   - In `tests/verify-install.sh`, verify section 4 and ensure test assertions align with the updated legacy message.
   - Verify that no em dashes exist anywhere in the repository.

5. **Seed canonical `~/.agents/review-refinements.md`**:
   - Perform a fresh read immediately before writing.
   - Add one domain-neutral, tool-agnostic bullet per pillar (8 total, preserving the existing Pillar 6 license attribution bullet).
   - Also update `templates/review-refinements.template.md` with corresponding seed bullets so fresh installations receive the starter principles.

6. **Verification gate**:
   - Diff the 8 pillar titles between `main` and `thematic-review-pillars.md` to confirm byte-identity.
   - Run `./tests/verify-install.sh` and ensure 100% pass rate.
   - Check bundle prose for any stray em dashes.
   - Update devlog with all changes, commits, and decisions.
