# Plan: Prefix Skills and Rename PR Comments Skill

## Thinking

The user selected the unified prefix pattern for all skills in the repository:
- `/agent-review-loop`
- `/agent-review-report`
- `/agent-review-pr-comments`

Currently, `agent-review-loop` and `agent-review-report` already follow this namespace convention. The third skill, `address-pr-comments`, is the only outlier. Renaming `skills/address-pr-comments` to `skills/agent-review-pr-comments` unifies the entire suite under the `agent-review-` namespace.

This change requires:
1. Renaming the directory from `skills/address-pr-comments` to `skills/agent-review-pr-comments` via git.
2. Updating `skills/agent-review-pr-comments/SKILL.md` (frontmatter name, description, usage commands).
3. Updating `skills/agent-review-pr-comments/agents/openai.yaml` (display metadata and prompt).
4. Updating `install.sh` to install, verify, and document `agent-review-pr-comments`. Optionally cleaning up legacy `address-pr-comments` directories during full install so stale versions do not linger.
5. Updating `tests/verify-install.sh` to test `agent-review-pr-comments` across all scenarios.
6. Updating cross-skill references in `skills/agent-review-report/SKILL.md` and `skills/agent-review-loop/thematic-review-pillars.md`.
7. Updating `README.md` (tables, paths, usage examples, uninstall, manual install).
8. Verifying zero em dashes and zero AI attributions.
9. Testing via `./tests/verify-install.sh` and updating the active installation.

## Plan

1. **Rename directory**:
   - `git mv skills/address-pr-comments skills/agent-review-pr-comments`.
2. **Update skill metadata**:
   - In `skills/agent-review-pr-comments/SKILL.md`: update `name: agent-review-pr-comments` and command invocations.
   - In `skills/agent-review-pr-comments/agents/openai.yaml`: update prompt and display name.
3. **Update cross-skill references**:
   - In `skills/agent-review-report/SKILL.md`: update suggested next step to `/agent-review-pr-comments`.
   - In `skills/agent-review-loop/thematic-review-pillars.md`: update skill list in header.
4. **Update installer & test harness**:
   - In `install.sh`: replace `address-pr-comments` with `agent-review-pr-comments` in `SKILLS`, `skill_files`, help text, and completion hint.
   - In `tests/verify-install.sh`: replace `address-pr-comments` with `agent-review-pr-comments`.
5. **Update README.md**:
   - Update skill descriptions, tables, invocation examples, uninstall snippets, and manual copy paths.
6. **Verify and test**:
   - Run `./tests/verify-install.sh` to ensure all tests pass.
   - Verify zero em dashes across the repository.
   - Re-run `./install.sh && ./install.sh --upgrade` and remove obsolete local `address-pr-comments` copies.
7. **Document**:
   - Log decision and changes in `devlog/000001-feat-generalize-review-criteria.md`.

### Legacy Migration Under Upgrade

When users run `./install.sh --upgrade`, existing `address-pr-comments` installations must not be skipped or left stale. To provide seamless backwards compatibility:
- `install.sh` defines `legacy_skill_name()` mapping `agent-review-pr-comments` to `address-pr-comments`.
- In `upgrade_skill()`: if `dest` is missing but `legacy_dest` exists, the installer detects the previous install, moves the directory (or repoints the symlink), refreshes it to `agent-review-pr-comments`, and removes the obsolete name.
- In `install_skill_copy()` and `install_skill_link()`: any leftover `legacy_dest` is automatically cleaned up.
- In `tests/verify-install.sh`: a test case explicitly verifies that `--upgrade` migrates `address-pr-comments` to `agent-review-pr-comments`.
