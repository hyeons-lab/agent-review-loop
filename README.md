# `agent-review-loop`

Three multi-agent review skills sharing one pillars file:
`agent-review-loop` reviews the working diff with subagents at a fixed
effort (`low`, `medium`, `high`, `max`), fixes what they find, and
re-reviews until clean; `agent-review-report` runs one report-only `max`
review over the working diff or a target PR and presents the findings;
and `agent-review-pr-comments` addresses review feedback on a target PR and
syncs the stack. All three file novel learnings as they go (each round,
each report, or each fix cycle for the PR skill), so later work reviews
against what the earlier work learned.
Each skill body runs in **Muse**, **Claude Code**, **Codex**, and
**Antigravity/Gemini**.

## Contents

- `skills/agent-review-loop/SKILL.md`: the skill (loop protocol, effort
  levels, verification gate, multi-agent pillar update rules).
- `skills/agent-review-loop/thematic-review-pillars.md`: the stable base
  pillars (8 categories). Loops read it; they never edit it.
- `skills/agent-review-loop/agents/openai.yaml`: Codex display metadata
  (ignored by other runtimes).
- `skills/agent-review-report/SKILL.md`: the report-only skill (one `max`
  review over the working diff or a target PR, findings to the user,
  PR posts only with explicit approval).
- `skills/agent-review-report/agents/openai.yaml`: Codex display metadata
  (ignored by other runtimes).
- `skills/agent-review-pr-comments/SKILL.md`: the PR feedback skill (fetch and
  triage comments, apply fixes, sync stacked PRs, file learnings).
- `skills/agent-review-pr-comments/agents/openai.yaml`: Codex display metadata
  (ignored by other runtimes).
- `templates/review-refinements.template.md`: seed for the shared learnings
  file that loops update.
- `install.sh`: idempotent installer (see below).
- `tests/verify-install.sh`: installer verification suite (runs against a
  fake `HOME`, never touches yours).

## Install

```bash
git clone https://github.com/hyeons-lab/agent-review-loop.git
cd agent-review-loop
./install.sh
```

Default installs the skills to every supported location and seeds the shared
refinements file. Pick targets to install fewer:

```bash
./install.sh --claude --codex        # only Claude Code and Codex
./install.sh --antigravity           # only Antigravity/Gemini (--gemini works too)
./install.sh --muse --agents         # only Muse and the canonical store
./install.sh --link                  # symlink agent dirs to one canonical copy
./install.sh --no-refinements        # skill only; do not seed the learnings file
./install.sh --upgrade               # refresh installed skills; learnings untouched
./install.sh --dry-run               # print what would change; change nothing
```

Each flag installs all three skills under its directory:

| Flag | Directory |
|---|---|
| `--agents` | `~/.agents/skills/{agent-review-loop,agent-review-report,agent-review-pr-comments}` (canonical store) |
| `--muse` | `$XDG_CONFIG_HOME/muse/skills/{agent-review-loop,agent-review-report,agent-review-pr-comments}` (`~/.config` by default) |
| `--claude` | `~/.claude/skills/{agent-review-loop,agent-review-report,agent-review-pr-comments}` |
| `--codex` | `~/.codex/skills/{agent-review-loop,agent-review-report,agent-review-pr-comments}` |
| `--antigravity` | `~/.gemini/config/skills/{agent-review-loop,agent-review-report,agent-review-pr-comments}` |

Restart the agent (or start a new session) after installing, then invoke:

```text
/agent-review-loop [low|medium|high|max]
/agent-review-report [<pr_number_or_url>]
/agent-review-pr-comments [<pr_number_or_url>]
```

Default effort for `agent-review-loop` is `high` (`agent-review-report`
always runs at `max`). The agent-neutral name sits alongside any
existing `review-fix-loop` skill without collision.

## Upgrade

```bash
cd agent-review-loop
git pull
./install.sh --upgrade
```

`--upgrade` refreshes every already-installed skill to the checked-out
version and verifies the result. It never installs to new locations,
never replaces symlinked installs, and never seeds or modifies
`~/.agents/review-refinements.md`, so accumulated learnings survive.
`--upgrade` ignores `--link`, always covers the canonical store so linked
installs refresh for real, and never adds a skill that is not already
installed: upgrading from a single-skill install needs one plain
`./install.sh` first to pick up new skills. Plain `./install.sh` also
preserves learnings but installs to every target; use `--upgrade` for a
refresh only. Run with `--dry-run` first to preview what would change.

## The Shared Pillars File

Loops file learnings under 8 fixed pillars (functional correctness,
security, concurrency, error handling, interface contracts, performance, code
simplification, and testing/observability). Resolution order:

1. `$REVIEW_REFINEMENTS_FILE` when set (explicit override).
2. Repo-local `.agents/review-refinements.md` (project specific; additive).
3. Canonical `~/.agents/review-refinements.md` (default target; all four
   runtimes read and write it).
4. Legacy `~/.gemini/review-refinements.md` (read only when
   `$REVIEW_REFINEMENTS_LEGACY=1` is set; skipped by default).

Multi-agent safety is built into the skill: one write target, a fresh read
immediately before every edit, automatic timestamped backups in `backups/`
with user pruning prompts when backups accumulate, surgical chunk replacement
scoped to single pillars, tool-agnostic bullets with no signatures, living
document evolution (adding or merging suggestions and cleaning up the total
bullets in each pillar so the file stays organized and evolves over time rather
than accumulating uncurated additions), and strict cross-stack generality.
Pillar numbers and titles are a frozen contract across loops.
Repo-specific lessons bootstrap a repo-local `.agents/review-refinements.md`
on demand, so each repo's reviews improve with use while general principles
accumulate in the canonical file. Standing rule: every bullet in canonical must
help a review in a different repo on a different stack; if it cannot be stated
that generally, abstract it or file it repo-local.

## Idempotency

- Re-running `./install.sh` reports `unchanged` for current skill files and
  `updated` only for files that differ. Skill files always refresh to the
  checked-out version, so keep local edits elsewhere.
- `~/.agents/review-refinements.md` is created from the template only when
  missing. It is never overwritten, merged, or reformatted. Existing
  learnings survive every reinstall. A legacy
  `~/.gemini/review-refinements.md` file is never touched; set
  `REVIEW_REFINEMENTS_LEGACY=1` to include it in reviews.
- `--link` converges too: correct links report `unchanged`, wrong ones are
  repointed, and switching back to a plain `./install.sh` replaces links
  with real copies.
- Verify any outcome with `./install.sh --dry-run`: only `[dry-run]`
  lines describe pending changes; `unchanged` lines mean current.

## Uninstall

```bash
rm -rf ~/.agents/skills/agent-review-loop ~/.agents/skills/agent-review-report ~/.agents/skills/agent-review-pr-comments \
  "${XDG_CONFIG_HOME:-$HOME/.config}/muse/skills/agent-review-loop" "${XDG_CONFIG_HOME:-$HOME/.config}/muse/skills/agent-review-report" "${XDG_CONFIG_HOME:-$HOME/.config}/muse/skills/agent-review-pr-comments" \
  ~/.claude/skills/agent-review-loop ~/.claude/skills/agent-review-report ~/.claude/skills/agent-review-pr-comments \
  ~/.codex/skills/agent-review-loop ~/.codex/skills/agent-review-report ~/.codex/skills/agent-review-pr-comments \
  ~/.gemini/config/skills/agent-review-loop ~/.gemini/config/skills/agent-review-report ~/.gemini/config/skills/agent-review-pr-comments
```

This leaves `~/.agents/review-refinements.md` in place. Delete it as well
only when you mean to discard your accumulated learnings.

## Manual Install

When a script is not wanted:

```bash
mkdir -p ~/.agents/skills/agent-review-loop/agents ~/.agents/skills/agent-review-report/agents ~/.agents/skills/agent-review-pr-comments/agents
cp skills/agent-review-loop/SKILL.md skills/agent-review-loop/thematic-review-pillars.md ~/.agents/skills/agent-review-loop/
cp skills/agent-review-loop/agents/openai.yaml ~/.agents/skills/agent-review-loop/agents/
cp skills/agent-review-report/SKILL.md ~/.agents/skills/agent-review-report/
cp skills/agent-review-report/agents/openai.yaml ~/.agents/skills/agent-review-report/agents/
cp skills/agent-review-pr-comments/SKILL.md ~/.agents/skills/agent-review-pr-comments/
cp skills/agent-review-pr-comments/agents/openai.yaml ~/.agents/skills/agent-review-pr-comments/agents/
# repeat the copies (or symlink) into any agent dir from the table above
[ -e ~/.agents/review-refinements.md ] || cp templates/review-refinements.template.md ~/.agents/review-refinements.md
```

## Contributing

Skill changes go in `skills/<name>/`; installer changes in `install.sh`.
Before pushing, run the verification suite (fake `HOME`, safe to run
anywhere):

```bash
./tests/verify-install.sh
```

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or
[MIT License](LICENSE-MIT) at your option.
