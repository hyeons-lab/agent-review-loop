# Plan: Automatic Timestamped Backups for Review Refinements

## Thinking

The user requested:
1. Create automatic timestamped backups before updating or consolidating `review-refinements.md`.
2. Ask the user if they want to remove old backups on a regular basis if the backups accumulate.

When an agent updates `review-refinements.md` (either canonical `~/.agents/review-refinements.md` or repo-local `.agents/review-refinements.md`), unintended clobbering, race conditions, or tool truncation can compromise accumulated review knowledge.

To protect this file:
1. **Automatic pre-edit backup**: Before applying any edit to `review-refinements.md`, the agent creates a dedicated backup directory (`$(dirname "$target")/backups`) and preserves a timestamped snapshot (`review-refinements-YYYYMMDD-HHMMSS.md`) using `cp -p`.
2. **Accumulation guard and user prompt**: The agent checks the total count of backup files in the `backups/` directory. If backups accumulate beyond a reasonable threshold (e.g. more than 5 backups), the agent proactively asks the user in chat whether they want to prune older backups while keeping the most recent 5. Older backups are never deleted silently without user consent.
3. **Surgical chunk editing invariant**: The agent is explicitly instructed to perform localized chunk replacements within the target pillar section and forbidden from overwriting the whole file.
4. **Structural invariant verification**: After the edit, the agent verifies that all 8 `### Pillar` headings remain intact byte-for-byte.
5. **Gitignore hygiene**: Add `.agents/backups/` to `.gitignore` so repo-local backup snapshots do not pollute git status.

This protocol must be codified in:
- `templates/review-refinements.template.md`
- `~/.agents/review-refinements.md`
- `skills/agent-review-loop/SKILL.md` (Section 6)
- `skills/agent-review-report/SKILL.md` (Section 7)
- `skills/agent-review-pr-comments/SKILL.md` (Section 3)
- `skills/agent-review-loop/thematic-review-pillars.md` (Section 3)
- `README.md`
- `.gitignore`
- `devlog/000001-feat-generalize-review-criteria.md`

## Plan

1. **Update .gitignore**: Add `.agents/backups/`.
2. **Update template and canonical refinements file**:
   - In `templates/review-refinements.template.md`: add rules for creating timestamped backups in `backups/` and prompting the user before pruning accumulated backups.
   - In `~/.agents/review-refinements.md`: synchronize the header rules.
3. **Update skills**:
   - In `skills/agent-review-loop/SKILL.md` Section 6: add Step 2b for automatic timestamped backup creation, accumulation check with user pruning prompt, and surgical chunk editing guard.
   - In `skills/agent-review-report/SKILL.md` Section 7: synchronize with the backup and pruning protocol.
   - In `skills/agent-review-pr-comments/SKILL.md` Section 3: synchronize with the backup and pruning protocol.
   - In `skills/agent-review-loop/thematic-review-pillars.md` Section 3: document backup creation and pruning check in the self-improvement protocol.
4. **Update README.md**:
   - Document automatic backups and accumulation management in the Shared Pillars File section.
5. **Verify**:
   - Run `./tests/verify-install.sh` to ensure all 137 tests pass.
   - Audit for zero em dashes across all touched files.
   - Run `./install.sh && ./install.sh --upgrade` to sync local environments.
6. **Log in devlog**:
   - Add decision, What Changed entries, and update the proposed commit in `devlog/000001-feat-generalize-review-criteria.md`.
