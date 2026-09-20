---
name: agent-review-loop
description: Review the working diff with subagents at a fixed effort, fix what they find, re-review until clean, and fold novel learnings back into the shared cross-agent review pillars. Works in Muse, Claude Code, Codex, and Antigravity/Gemini.
---

# Review Fix Loop (Multi-Agent)

Iterate the current working diff to a clean code review, then make the next
review stronger: spawn review **subagents** at a fixed effort level, fix the
issues they report, then spawn fresh reviewers again at the **same** effort.
Repeat until a round reports no issues or only micro-nitpicks. When the loop
ends, generalize anything the loop learned into the shared pillars file so
every review loop that shares that file reviews against it next time.

This skill runs in Muse, Claude Code, Codex, and Antigravity/Gemini, and it
runs autonomously without external PR calls. Section 5 maps each runtime to
its native subagent mechanism. Use the row that matches your runtime. When
your runtime offers no subagent tool at all, use the sequential fallback in
that same table.

## 1. Core Invariants

1. **Zero AI attribution**: never attribute yourself or any AI assistant in
   commits, PR descriptions, code comments, docstrings, or prose.
2. **Punctuation**: never write an em dash (U+2014) or lookalikes (`--` or
   spaced hyphens) in anything you write. Use colons, commas, semicolons,
   parentheses, or separate sentences.
3. **Commit invariants**:
   - Only commit at the end of the entire loop, after reaching a clean review
     or nitpicks-only state.
   - Never commit, push, tag, or amend without explicit human approval in this
     session. Finishing the loop is not approval.
   - Follow the repository's own commit convention (repo docs win over any
     default; never add attribution or trailer lines).
4. **Verification gate**: everything must compile, the repo's own format and
   static-analysis gates must be clean, and the relevant tests must pass
   before a round or commit counts as complete.

## 2. Review Depth (Effort Level)

Arguments may specify the effort: `low`, `medium`, `high`, or `max`.
Default is **`high`**.

- **`low`**: shallow scan for high-impact correctness bugs, broken invariants,
  and leftover debug clutter. 1 reviewer.
- **`medium`**: thorough audit of correctness, edge cases, project guidelines,
  and simplification. 2 parallel reviewers with complementary lenses.
- **`high`** (default): deep audit across all 8 pillars below. 4 parallel
  reviewers, each owning 2 pillars, plus a synthesis pass over their reports.
- **`max`**: exhaustive audit, one reviewer per pillar (8 parallel), with a
  second synthesis reviewer reconciling overlaps before you see the report.

The chosen effort is **fixed for the entire loop**. Every round runs at the
same effort and fan-out. Never escalate or de-escalate between rounds. An
unknown argument counts as no effort given: use the default and say so.

When your runtime caps concurrent subagents, run the round's reviewers in
waves inside the same round. Coverage stays fixed; only the scheduling bends.

## 3. Review Criteria: Base Pillars Plus Shared Learnings

Two tiers, same contract in every runtime:

1. **Base pillars** (stable defaults): `thematic-review-pillars.md`, bundled
   in this skill's directory. Read it at loop start. Loops never edit it.
   When your runtime cannot resolve the skill directory, fall back to the 8
   pillar names listed in section 5, step 1.
2. **Shared learnings** (evolving): read every file below that exists and
   audit against the union. On a direct conflict, the more specific file
   wins (repo-local first, then canonical, then legacy):
   - `$REVIEW_REFINEMENTS_FILE` when set (explicit override).
   - Canonical `~/.agents/review-refinements.md` (default write target;
     every supported agent reads it).
   - Legacy `~/.gemini/review-refinements.md` (read only; kept so older
     loops keep contributing).
   - Repo-local `.agents/review-refinements.md` (project specific; read in
     addition when present).

## 4. Diff Extraction and Noise Filtering

Review the **working-tree diff** (staged plus unstaged). When the tree is
clean but the branch is ahead of its base, review the **branch diff**
(`git diff <base>...HEAD`, base from the merge-base with the default branch).
Inside a worktree, run every `git` command with `git -C <worktree>`.

Filter out lockfiles, generated code, and binary artifacts before reviewing:

```bash
git --no-pager diff HEAD -- . \
  ':!*.lock' ':!Cargo.lock' ':!package-lock.json' ':!pnpm-lock.yaml' ':!uv.lock' \
  ':!target' ':!dist' ':!build' ':!node_modules' \
  ':!*.onnx*' ':!*.gguf' ':!*.wasm' ':!*.dylib' ':!*.so' ':!*.dll' \
  ':!**/generated/**' ':!devlog/**' ':!docs/**'
```

Save the filtered diff to a scratch file under `/tmp` so reviewers can
inspect it without context truncation. Never review a diff you have not
read; never let a reviewer report stand in for reading the changed code.

## 5. The Loop Protocol

Maintain a round counter `n` starting at 1 with a safety cap of **10**
rounds. Stop with a status report if the cap hits with actionable items left.

### Step 1: Run the review round

Spawn the review subagents for the chosen effort, then collect every report
before proceeding. Each reviewer audits the filtered diff plus the
surrounding source it needs (callers, types, tests, configs) against the
**8 Core Thematic Pillars**:

1. Low-Level Safety, Alignment & Buffer Invariants
2. Concurrency, Cancellation & State Machine Lifecycles
3. Error Propagation, Diagnostics & No-Panic Invariants
4. Multiplatform Portability & Cross-Binding Drift
5. Numerical Robustness & Boundary Validation
6. Pipeline Completeness & Contract Faithfulness
7. Performance, SIMD & Resource Efficiency
8. Code Simplification, Cleanup & Complexity Reduction

Use your runtime's row. Every reviewer in the round reports before you
classify anything.

| Runtime | How to spawn one reviewer per lens | How to collect |
|---|---|---|
| Muse | `subagent_spawn`, one child per reviewer in a single fan-out | `subagent_wait` on every child before classifying |
| Claude Code | `Task` tool, one call per reviewer, all calls issued together in a single block | every call returns its report; proceed only when all have returned |
| Codex | `spawn_agent` collaboration subagents; check `list_agents` first and never disturb unrelated agents; unique task names per round (for example `review_r3_correctness`) | wait for every reviewer in the round |
| Antigravity/Gemini | `invoke_subagent` with `TypeName` self or research and a distinct `Role` per reviewer | one call launches the round concurrently |
| Any other runtime | Sequential fallback: run one review pass per lens yourself, re-reading the diff fresh for each pass so earlier passes never narrow later ones | all passes complete before classifying |

Every reviewer prompt must include:

- The embedded filtered diff (or its `/tmp` path when large).
- The instruction to read the repo's own guidance first (`AGENTS.md`,
  `CLAUDE.md`, `GEMINI.md`, `.editorconfig`, CI workflows), the bundled base
  pillars, and every shared learnings file that exists.
- A read-only rule: reviewers report findings and edit nothing.
- The finding format: `SEVERITY | file_path:line_number | one-line
  description | why it matters`, with `SEVERITY` in `bug`, `correctness`,
  `convention`, `quality`, or `nitpick`. Every non-nitpick needs a hazard
  explanation and a concrete fix (before and after code), not a generic
  summary. A reviewer with nothing to report returns exactly `NO FINDINGS`.

Merge and de-duplicate reports by `file_path:line_number` plus underlying
defect before classifying.

### Step 2: Classify findings and check the stop condition

- **Clean**: every reviewer returned `NO FINDINGS`.
- **Nitpicks Only**: every finding has `nitpick` severity (cosmetic
  formatting, doc phrasing, or trivial preferences only).
- **Actionable**: anything else (correctness risks, safety hazards,
  unbounded waits, leaks, contract drift, missing coverage).

If **Clean** or **Nitpicks Only**: apply safe nitpicks in one final pass,
run the full verification gate, update the pillars (section 6), and proceed
to Finishing Up.

Treat reviewer disagreement as signal, not noise: if two reviewers
contradict each other, resolve the conflict against the code before fixing.

### Step 3: Apply fixes

Make precise, focused edits for every actionable item with your
environment's file editing tools. Keep each fix minimal and
behavior-scoped; do not refactor around a finding. If a fix is large or
structurally risky (broad refactor, API change, control flow with blast
radius), stop and ask the user before applying it.

### Step 4: Verification gate

Discover and run the repository's own gates; never substitute generic
checks. Read the CI workflows and project docs first, then at minimum:

- Format gate clean (whatever CI enforces).
- Static analysis / linters clean for every affected language.
- The full test files or packages covering the touched areas, run
  unmodified. A red test after your change is a requirement, not a stale
  artifact: fix the change, never weaken or skip the test.
- The punctuation invariant holds in everything you wrote or edited.

### Step 5: Round summary

Report between rounds, briefly:

- **Round `n` findings**: issues, warnings, suggestions (one line each).
- **Fixes applied**: files and what changed.
- **Verification status**: gates run and their results.

### Step 6: Advance

Increment `n` and loop back to Step 1.

## 6. Pillar Update (Shared Learnings, Multi-Agent Safe)

The loop earns its keep twice: once in the fixed diff, once in the next
review. After the stop condition is met (or the cap forces a stop), fold
genuinely novel learnings into the shared file. Several agents share this
file, so the target selection and the fresh-read rule below are load
bearing.

Pick the write target in order:

1. `$REVIEW_REFINEMENTS_FILE` when set: write there.
2. A repo-specific lesson (it names this repo's modules, crates, tools, CI
   jobs, or architectures): file it in the repo's own
   `.agents/review-refinements.md`, creating that file with the 8
   `### Pillar N:` headings when it does not exist yet. This is how each
   repo's reviews get sharper over time: repo invariants accumulate in the
   repo, general principles accumulate in the canonical file. Leave the
   repo-local file uncommitted; it goes out only with the user's approved
   commit.
3. Otherwise the canonical `~/.agents/review-refinements.md`. When it does
   not exist yet, create it with the 8 `### Pillar N:` headings (copy their
   exact titles from the bundled base pillars file), then append.
4. Never write the legacy `~/.gemini/review-refinements.md` path. Older
   loops may still append there; this loop only reads it. Routing all new
   writes through one target keeps learnings from splitting across files.

Re-read the target file immediately before editing, in the same step as
the write. Never edit from the copy loaded at loop start; another loop may
have filed bullets since. When a fresh read shows your lesson already
covered, subsume instead of duplicating.

Rules:

1. **Subsumption first**: if an existing bullet under a pillar already covers
   the lesson, refine that bullet instead of adding a sibling.
2. **Generalize**: write the principle the finding taught (trigger, hazard,
   fix shape), not the instance. One bullet must help a future review in a
   different file.
3. **File under the right pillar**: match the finding to one of the 8
   `### Pillar N:` sections. Never add a 9th pillar or rename one; every
   loop addresses pillars by number.
4. **Stay bounded**: at most 5 new or refined bullets per loop run. Skip
   anything already covered, anything repo-specific trivia, and anything you
   are not confident will recur.
5. **Append-only discipline**: add or refine bullets only. Never delete or
   rewrite another loop's bullets, and never reformat the file.
6. **Tool-agnostic bullets**: state trigger, hazard, and fix shape. Never
   name an agent, model, runtime, or assistant tool in a bullet.
7. **No signatures**: no author, date, or source tags on bullets. Shared
   history lives outside the file.
8. **Merge across loops**: when a bullet filed by another loop overlaps
   yours, extend that bullet's trigger list instead of adding a
   near-duplicate.

If the loop surfaced nothing novel, say so and leave the file untouched.

## 7. Finishing Up

1. **Cumulative summary**: total rounds, every issue/warning/optimization
   addressed across rounds, verification results, and which pillar bullets
   were added or refined (with pillar numbers).
2. **Approval for commit and push**: do not commit or push on your own.
   Present the proposed commit message in the repo's convention and ask for
   explicit confirmation first.
