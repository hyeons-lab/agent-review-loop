---
name: agent-review-loop
description: Review the working diff with subagents at a fixed effort, fix what they find, re-review until clean, and fold novel learnings back into the shared cross-agent review pillars. Works in Muse, Claude Code, Codex, and Antigravity/Gemini.
---

# Review Fix Loop (Multi-Agent)

Iterate the current working diff to a clean code review, then make the next
review stronger: spawn review **subagents** at a fixed effort level, fix the
issues they report, then spawn fresh reviewers again at the **same** effort.
Repeat until a round reports no issues or only micro-nitpicks. After every
round, generalize what that round learned into the shared pillars file, so
each round reviews against what the previous rounds learned instead of only
the next loop benefiting.

This skill runs in Muse, Claude Code, Codex, and Antigravity/Gemini, and it
runs autonomously without external PR calls. Section 5 maps each runtime to
its native subagent mechanism. Use the row that matches your runtime. When
your runtime offers no subagent tool at all, use the sequential fallback in
that same table.

## 1. Core Invariants

1. **Zero AI attribution**: never attribute yourself or any AI assistant in
   commits, PR descriptions, code comments, docstrings, or prose.
2. **Punctuation**: never write an em dash (U+2014), and never use `--`
   or spaced hyphens as punctuation in prose. `--` stays allowed in
   command flags, code, and quoted output. In prose, use colons, commas,
   semicolons, parentheses, or separate sentences.
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
5. **Pillar stability**: review against the 8 canonical software engineering
   pillars in section 5, step 1 by number and name, exactly as listed.
   Never substitute a custom, legacy, or domain-specific pillar set:
   shared learnings are filed by canonical pillar number and title, so a
   renamed set orphans every bullet and breaks downstream review loops.

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

The chosen effort is **fixed for the entire loop** except for the
user-approved quiet-round step-down below. Every round runs at the same
effort and fan-out. Never escalate, and never de-escalate except through
that step-down. An unknown argument counts as no effort given: use the
default and say so.

Choose the effort from the diff, not from habit: unfamiliar code, large
diffs, or security-sensitive areas earn `max`; small follow-ups on a
recently reviewed diff do fine at `low` or `medium`. When three
consecutive rounds each yield at most one finding and none above `quality`
severity (no `bug`, `correctness`, or `convention` findings), propose
dropping one level to the user rather than burning full rounds; continue
at the lower effort only with explicit approval.

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
   - Repo-local `.agents/review-refinements.md` (project specific; read in
     addition when present).
   - Canonical `~/.agents/review-refinements.md` (default write target;
     every supported agent reads it).
   - Legacy `~/.gemini/review-refinements.md` (read only when
     `$REVIEW_REFINEMENTS_LEGACY=1` is set; skipped by default so
     repo-specific inference lessons do not pollute other projects).

## 4. Diff Extraction and Noise Filtering

Review the **working-tree diff** (staged plus unstaged). When the tree is
clean but the branch is ahead of its base, review the **branch diff**
(`git diff <base>...HEAD`, base from the merge-base with the default branch).
Inside a worktree, run every `git` command with `git -C <worktree>`.

Filter out lockfiles, generated code, and binary artifacts before reviewing:

```bash
if git diff --quiet HEAD -- .; then
  base="$(git merge-base origin/main HEAD 2>/dev/null || git merge-base main HEAD 2>/dev/null || echo "origin/main")"
  diff_target="${base}...HEAD"
else
  diff_target="HEAD"
fi

diff_file="$(mktemp "${TMPDIR:-/tmp}/agent-review-loop-diff.XXXXXX")"
git --no-pager diff "${diff_target}" -- . \
  ':!**/*.lock' ':!**/Cargo.lock' ':!**/package-lock.json' ':!**/pnpm-lock.yaml' ':!**/uv.lock' \
  ':!**/target/**' ':!**/dist/**' ':!**/build/**' ':!**/node_modules/**' \
  ':!**/*.onnx*' ':!**/*.gguf' ':!**/*.wasm' ':!**/*.dylib' ':!**/*.so' ':!**/*.dll' \
  ':!**/generated/**' ':!devlog/**' ':!docs/**' > "$diff_file"
```

Save the filtered diff to a scratch file so reviewers can
inspect it without context truncation. Clean up the scratch file when the loop
finishes. Never review a diff you have not read; never let a reviewer report
stand in for reading the changed code.

## 5. The Loop Protocol

Maintain a round counter `n` starting at 1 with a safety cap of **10**
rounds. Stop with a status report if the cap hits with actionable items left.

### Step 1: Run the review round

Spawn the review subagents for the chosen effort, then collect every report
before proceeding. Each reviewer audits the filtered diff plus the
surrounding source it needs (callers, types, tests, configs) against the
**8 Canonical Thematic Pillars**:

1. Functional Correctness, Logic & Edge Cases
2. Security, Authentication & Input Sanitization
3. Concurrency, Asynchrony & Lifecycle Management
4. Error Handling, Resilience & Diagnostics
5. Interface Contracts, API Design & Compatibility
6. Performance, Resource Efficiency & Scalability
7. Code Simplification, Clean Architecture & Maintainability
8. Testing, Observability & Verification Invariants

Assign reviewer roles using the exact canonical pillar names:
- `max` (8 parallel reviewers): one reviewer per pillar, using the exact
  pillar number and name (e.g. `Reviewer 1: Functional Correctness, Logic & Edge Cases`).
- `high` (4 parallel reviewers): paired canonical pillars:
  - Reviewer 1: Pillars 1 & 2 (Correctness & Security)
  - Reviewer 2: Pillars 3 & 4 (Concurrency & Error Handling)
  - Reviewer 3: Pillars 5 & 6 (Contracts/API & Performance)
  - Reviewer 4: Pillars 7 & 8 (Simplification & Testing)
- `medium` (2 parallel reviewers):
  - Reviewer 1: Pillars 1-4 (Correctness, Security, Concurrency, Error Handling)
  - Reviewer 2: Pillars 5-8 (Contracts/API, Performance, Simplification, Testing)
- `low` (1 reviewer): all 8 canonical pillars.

Use your runtime's row. Every reviewer in the round reports before you
classify anything. If a reviewer has not reported within the runtime
default timeout, re-prompt it once; if still silent, cancel or terminate the
subagent if your runtime supports it, proceed with the reports in hand, note
the missing lens in the round summary, and treat its pillars as uncovered next
round.

<!-- Mirrored with skills/agent-review-report/SKILL.md: keep runtime rows in sync. -->
| Runtime | How to spawn one reviewer per lens | How to collect |
|---|---|---|
| Muse | `subagent_spawn`, one child per reviewer in a single fan-out | `subagent_wait` on every child before classifying |
| Claude Code | `Task` tool, one call per reviewer, all calls issued together in a single block | every call returns its report; proceed only when all have returned |
| Codex | `spawn_agent` collaboration subagents; check `list_agents` first and never disturb unrelated agents; unique task names per round (for example `review_r3_correctness`) | wait for every reviewer in the round |
| Antigravity/Gemini | `invoke_subagent` with `TypeName` self or research and a distinct `Role` per reviewer | the call blocks until every reviewer in the round has reported; proceed only when all reports are in |
| Any other runtime | Sequential fallback: run one review pass per lens yourself, re-reading the diff fresh for each pass so earlier passes never narrow later ones | all passes complete before classifying |

Every reviewer prompt must include:

- The scratch path of the filtered diff saved in section 4, plus its line
  count. The reviewer quotes both back in the report header, so a scope
  mismatch (stale diff, wrong worktree) is visible before anything else.
  Embed the diff text only when it is small enough to fit comfortably.
- The instruction to read the repo's own guidance first (`AGENTS.md`,
  `CLAUDE.md`, `GEMINI.md`, `.editorconfig`, CI workflows), the bundled base
  pillars, and every shared learnings file that exists.
- For rounds after the first: pass ONLY the bullets newly added or refined
  during THIS review loop run (tracked in your round summaries), quoted
  verbatim under their canonical pillar number and title
  (for example: `Bullets filed this loop: - Pillar 1: Title: ...`).
  Do not pass pre-existing bullets from the refinements file into this list.
- A read-only rule: reviewers report findings and edit nothing.
- An execution rule: behavior claims must be checked by running the repo's
  own tests or a minimal reproduction, quoted as command plus result. A
  claim that a test pins a behavior must be proven non-vacuous: show the
  test fails with the fix reverted (or the behavior present without the
  guard). Reading alone is not evidence for behavior.
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
run the Step 4 fix check on those edits (a main-agent direct check
suffices), then the full verification gate, the final pillar sweep
(section 6), and proceed to Finishing Up.

Treat reviewer disagreement as signal, not noise: if two reviewers
contradict each other, resolve the conflict against the code before fixing.

### Step 3: Apply fixes

Make precise, focused edits for every actionable item with your
environment's file editing tools. Keep each fix minimal and
behavior-scoped; do not refactor around a finding. If a fix is large or
structurally risky (broad refactor, API change, control flow with blast
radius), stop and ask the user before applying it.

### Step 4: Fix check (targeted re-review)

Before spending a full round, confirm the Step 3 edits hold. Scope is only
the changed hunks plus their immediate callers and tests: one reviewer at
`low`, or the main agent directly when the fix is small. Check three
things: each fix addresses its finding; the fix broke none of its own
preconditions (fast paths that bypass the fixed code, no-op contracts,
error mappings); every new or changed test is non-vacuous (fails with the
fix reverted). When the check finds a regression, fix it and repeat this
step (at most 3 attempts total). If the third attempt still shows a
regression, stop and ask the user how to proceed; never launch a full
round on a fix known to be broken.

### Step 5: Verification gate

Discover and run the repository's own gates; never substitute generic
checks. Read the CI workflows and project docs first, then at minimum:

- Format gate clean (whatever CI enforces).
- Static analysis / linters clean for every affected language.
- The full test files or packages covering the touched areas, run
  unmodified. A red test after your change is a requirement, not a stale
  artifact: fix the change, never weaken or skip the test.
- The punctuation invariant holds in everything you wrote or edited.

### Step 6: Round summary and learning capture

Report between rounds, briefly:

- **Round `n` findings**: issues, warnings, suggestions (one line each).
- **Fixes applied**: files and what changed.
- **Verification status**: gates run and their results.
- **Learnings filed**: pillar bullets added or refined this round (with
  canonical pillar numbers and titles), or `none` with one line on why the
  round taught nothing durable.

Then file this round's learnings immediately, per section 6. Do not batch
them for loop end: the next round's reviewers read them (Step 1), so each
round reviews against what the previous rounds learned. Filing is a mandatory
step of the round: you must use your file editing tool to write or refine the
bullets in the target refinements file on disk before advancing. A round is
not complete until its learnings are written to disk or explicitly skipped
as non-novel.

### Step 7: Advance

Increment `n` and loop back to Step 1.

## 6. Pillar Update (Shared Learnings, Multi-Agent Safe)

The loop earns its keep twice: once in the fixed diff, once in the next
review. File learnings after every round (Step 6), not at loop end: each
round's reviewers read what earlier rounds filed, so the loop gets sharper
while it runs instead of only the next loop. When the stop condition is met
(or the cap forces a stop), run one final sweep for loop-level lessons only
(patterns visible across rounds but in no single round). Several agents
share this file, so the target selection, fresh-read rule, and placement
discipline below are load bearing.

### Target Selection Order

Pick the write target in order:

1. `$REVIEW_REFINEMENTS_FILE` when set: write there.
2. A repo-specific lesson (it names this repo's modules, crates, tools, CI
   jobs, or architectures): file it in the repo's own
   `.agents/review-refinements.md`, creating that file with the 8
   `### Pillar N:` headings when it does not exist yet. This is how each
   repo's reviews get sharper over time: repo invariants accumulate in the
   repo, general principles accumulate in the canonical file. Do not commit
   the repo-local file on your own; include it only in a commit the user
   explicitly approved.
3. Otherwise the canonical `~/.agents/review-refinements.md`. Standing rule:
   every filed bullet must help a review in a different repo on a different
   stack; if it cannot be stated that generally, abstract it or file it
   repo-local. When canonical does not exist yet, create it with the 8
   `### Pillar N:` headings (copy their exact titles from the bundled base
   pillars file), then append.
4. Never write the legacy `~/.gemini/review-refinements.md` path. It is read
   only when `$REVIEW_REFINEMENTS_LEGACY=1` is set; all new writes go to
   canonical or repo-local.

### How to Update the Refinements File Correctly

Follow this exact sequence whenever filing learnings:

1. **Fresh re-read**: View the target file immediately before editing, in the
   same step as the write. Never edit from a copy loaded at round start;
   another loop may have filed bullets in the interim.
2. **Classify under the exact canonical pillar**: Match the lesson to one of
   the 8 canonical headings:
   - `### Pillar 1: Functional Correctness, Logic & Edge Cases`
   - `### Pillar 2: Security, Authentication & Input Sanitization`
   - `### Pillar 3: Concurrency, Asynchrony & Lifecycle Management`
   - `### Pillar 4: Error Handling, Resilience & Diagnostics`
   - `### Pillar 5: Interface Contracts, API Design & Compatibility`
   - `### Pillar 6: Performance, Resource Efficiency & Scalability`
   - `### Pillar 7: Code Simplification, Clean Architecture & Maintainability`
   - `### Pillar 8: Testing, Observability & Verification Invariants`
   Never invent custom pillar titles, rename a pillar, or add a 9th pillar.
3. **Subsumption first**: Read existing bullets under that pillar's heading.
   If an existing bullet already covers the core failure mode, edit that
   bullet in place to broaden its trigger condition or refine its fix shape.
   Do not add near-duplicate siblings.
4. **Format the bullet**: Each bullet must adhere to the exact structure:
   `- **Title**: Trigger condition (when doing X): hazard or failure mode (Y occurs); fix shape and verification guidance (fix by doing Z, and verify via W).`
   - Single bullet starting with `- **Title**:`.
   - Title in Title Case (2 to 5 words).
   - Domain-neutral trigger, hazard, and fix shape.
   - Tool-agnostic: never name an agent, model, runtime, or assistant tool.
   - Zero attribution: no signatures, author tags, dates, or loop IDs.
   - Punctuation invariants: zero em dashes (U+2014) or `--` / spaced hyphens
     as punctuation lookalikes. Use standard ASCII punctuation (colons, commas,
     semicolons, parentheses, periods).
5. **Exact file placement**:
   - If refining an existing bullet, replace it in place.
   - If adding a new bullet, insert it directly under the appropriate
     `### Pillar N:` heading (below `<!-- Loops append bullets here. -->` or
     after existing bullets in that section, strictly before the next
     `### Pillar` heading).
   - Never append bullets at the end of the file outside a pillar section.
6. **Immediate read-back**: View the modified lines with a file viewing tool
   to confirm correct placement, valid markdown, and preserved pillar structure.
7. **Stay bounded**: At most 2 new or refined bullets per round, at most 5
   per loop run including the final sweep. If the round surfaced nothing
   durable or novel, leave the file untouched and report `Learnings filed: none`.

## 7. Finishing Up

1. **Cumulative summary**: total rounds, every issue/warning/optimization
   addressed across rounds, verification results, and which pillar bullets
   were added or refined per round (with pillar numbers).
2. **Approval for commit and push**: do not commit or push on your own.
   Present the proposed commit message in the repo's convention and ask for
   explicit confirmation first.
