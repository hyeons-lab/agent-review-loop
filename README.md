# `agent-review-loop`

A multi-agent code review skill: it reviews the working diff with subagents
at a fixed effort (`low`, `medium`, `high`, `max`), fixes what they find,
re-reviews until clean, and files novel learnings into a shared pillars file
so the next review starts smarter. One skill body runs in **Muse**,
**Claude Code**, **Codex**, and **Antigravity/Gemini**; a runtime adapter
inside the skill picks the native subagent mechanism for each.

## Contents

- `skills/agent-review-loop/SKILL.md`: the skill (loop protocol, effort
  levels, verification gate, multi-agent pillar update rules).
- `skills/agent-review-loop/thematic-review-pillars.md`: the stable base
  pillars (8 categories). Loops read it; they never edit it.
- `skills/agent-review-loop/agents/openai.yaml`: Codex display metadata
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

Default installs the skill to every supported location and seeds the shared
refinements file. Pick targets to install fewer:

```bash
./install.sh --claude --codex        # only Claude Code and Codex
./install.sh --antigravity           # only Antigravity/Gemini (--gemini works too)
./install.sh --muse --agents         # only Muse and the canonical store
./install.sh --link                  # symlink agent dirs to one canonical copy
./install.sh --no-refinements        # skill only; do not seed the learnings file
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
```

Default effort is `high`. The agent-neutral name sits alongside any
existing `review-fix-loop` skill without collision.

## Upgrade

```bash
cd agent-review-loop
git pull
./install.sh
```

Skill files refresh to the checked-out version; your learnings stay. Run
with `--dry-run` first to preview what would change.

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
subsumption over duplication, append-only discipline, and a 5-bullet cap
per loop run. Pillar numbers and titles are a frozen contract across loops.
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
rm -rf ~/.agents/skills/agent-review-loop \
  ~/.config/muse/skills/agent-review-loop \
  ~/.claude/skills/agent-review-loop \
  ~/.codex/skills/agent-review-loop \
  ~/.gemini/config/skills/agent-review-loop
```

This leaves `~/.agents/review-refinements.md` in place. Delete it as well
only when you mean to discard your accumulated learnings.

## Manual Install

When a script is not wanted:

```bash
SKILL=agent-review-loop
mkdir -p ~/.agents/skills/$SKILL
cp skills/$SKILL/SKILL.md skills/$SKILL/thematic-review-pillars.md ~/.agents/skills/$SKILL/
mkdir -p ~/.agents/skills/$SKILL/agents
cp skills/$SKILL/agents/openai.yaml ~/.agents/skills/$SKILL/agents/
# repeat the copies (or symlink) into any agent dir from the table above
[ -e ~/.agents/review-refinements.md ] || cp templates/review-refinements.template.md ~/.agents/review-refinements.md
```

## Contributing

Skill changes go in `skills/agent-review-loop/`; installer changes in
`install.sh`. Before pushing, run the verification suite (fake `HOME`, safe
to run anywhere):

```bash
./tests/verify-install.sh
```
