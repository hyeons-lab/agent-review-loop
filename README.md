# `agent-review-loop`

Two multi-agent review skills sharing one pillars file: `agent-review-loop`
reviews the working diff with subagents at a fixed effort (`low`, `medium`,
`high`, `max`), fixes what they find, and re-reviews until clean, while
`address-pr-comments` addresses review feedback on a target PR and syncs the
stack. Both file novel learnings into the shared pillars file after every
round, so each round reviews against what the previous rounds learned.
Each skill body runs in **Muse**, **Claude Code**, **Codex**, and
**Antigravity/Gemini**.

## Contents

- `skills/agent-review-loop/SKILL.md`: the skill (loop protocol, effort
  levels, verification gate, multi-agent pillar update rules).
- `skills/agent-review-loop/thematic-review-pillars.md`: the stable base
  pillars (8 categories). Loops read it; they never edit it.
- `skills/agent-review-loop/agents/openai.yaml`: Codex display metadata
  (ignored by other runtimes).
- `skills/address-pr-comments/SKILL.md`: the PR feedback skill (fetch and
  triage comments, apply fixes, sync stacked PRs, file learnings).
- `skills/address-pr-comments/agents/openai.yaml`: Codex display metadata
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

| Flag | Directory |
|---|---|
| `--agents` | `~/.agents/skills/agent-review-loop` (canonical store) |
| `--muse` | `$XDG_CONFIG_HOME/muse/skills/agent-review-loop` (`~/.config` by default) |
| `--claude` | `~/.claude/skills/agent-review-loop` |
| `--codex` | `~/.codex/skills/agent-review-loop` |
| `--antigravity` | `~/.gemini/config/skills/agent-review-loop` |

Restart the agent (or start a new session) after installing, then invoke:

```text
/agent-review-loop [low|medium|high|max]
/address-pr-comments <pr_number_or_url>
```

Default effort is `high`. The agent-neutral name sits alongside any
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
`~/.agents/review-refinements.md`, so accumulated learnings survive. Plain
`./install.sh` also preserves learnings but installs to every target; use
`--upgrade` for a refresh only. Run with `--dry-run` first to preview what
would change.

## The Shared Pillars File

Loops file learnings under 8 fixed pillars (low-level safety, concurrency,
error propagation, portability, numerical robustness, pipeline completeness,
performance, simplification). Resolution order:

1. `$REVIEW_REFINEMENTS_FILE` when set (explicit override).
2. Canonical `~/.agents/review-refinements.md` (default target; all four
   runtimes read and write it).
3. Legacy `~/.gemini/review-refinements.md` (read only; existing files keep
   working, new bullets go to the canonical path).
4. Repo-local `.agents/review-refinements.md` (project specific; additive).

Multi-agent safety is built into the skill: one write target, a fresh read
immediately before every edit, tool-agnostic bullets with no signatures,
subsumption over duplication, append-only discipline, and a 2-bullet cap
per round (5 per loop run). Pillar numbers and titles are a frozen
contract across loops.
Repo-specific lessons bootstrap a repo-local `.agents/review-refinements.md`
on demand, so each repo's reviews improve with use while general principles
accumulate in the canonical file.

## Idempotency

- Re-running `./install.sh` reports `unchanged` for current skill files and
  `updated` only for files that differ. Skill files always refresh to the
  checked-out version, so keep local edits elsewhere.
- `~/.agents/review-refinements.md` is created from the template only when
  missing. It is never overwritten, merged, or reformatted. Existing
  learnings (including a legacy `~/.gemini/review-refinements.md`, which is
  never touched) survive every reinstall.
- `--link` converges too: correct links report `unchanged`, wrong ones are
  repointed, and switching back to a plain `./install.sh` replaces links
  with real copies.
- Verify any outcome with `./install.sh --dry-run`: empty output means
  nothing would change.

## Uninstall

```bash
rm -rf ~/.agents/skills/agent-review-loop ~/.agents/skills/address-pr-comments \
  ~/.config/muse/skills/agent-review-loop ~/.config/muse/skills/address-pr-comments \
  ~/.claude/skills/agent-review-loop ~/.claude/skills/address-pr-comments \
  ~/.codex/skills/agent-review-loop ~/.codex/skills/address-pr-comments \
  ~/.gemini/config/skills/agent-review-loop ~/.gemini/config/skills/address-pr-comments
```

This leaves `~/.agents/review-refinements.md` in place. Delete it as well
only when you mean to discard your accumulated learnings.

## Manual Install

When a script is not wanted:

```bash
mkdir -p ~/.agents/skills/agent-review-loop/agents ~/.agents/skills/address-pr-comments/agents
cp skills/agent-review-loop/SKILL.md skills/agent-review-loop/thematic-review-pillars.md ~/.agents/skills/agent-review-loop/
cp skills/agent-review-loop/agents/openai.yaml ~/.agents/skills/agent-review-loop/agents/
cp skills/address-pr-comments/SKILL.md ~/.agents/skills/address-pr-comments/
cp skills/address-pr-comments/agents/openai.yaml ~/.agents/skills/address-pr-comments/agents/
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
