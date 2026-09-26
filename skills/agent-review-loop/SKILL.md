---
name: agent-review-loop
description: Review the working diff with subagents at a fixed effort, fix what they find, re-review until clean, and fold novel learnings back into the shared cross-agent review pillars. Works in Muse, Claude Code, Codex, and Antigravity/Gemini.
---

# Review Fix Loop (Multi-Agent)

Iterate the current working diff to a clean code review, then make the next
review stronger: spawn review **subagents** at a fixed effort level, fix the
issues they report, then spawn fresh reviewers again at the **same** effort
but scoped to the dirty set: the lenses that reported actionable findings,
plus any flagged or missing lens (section 5, steps 1 and 7). Repeat until
the narrowed rounds go clean or nitpicks-only, confirming each clean or
nitpicks-only subset with a full round in case the fixes moved a problem
into another pillar. After every
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
6. **Credential redaction**: ensure secrets, API keys, passwords, and private
   tokens are redacted from round summaries and every progress heartbeat
   file in the run (pillar reviewers, synthesis, fix-check, and
   replacements); use placeholders like `<REDACTED_SECRET>` instead.

## 2. Review Depth (Effort Level)

Arguments may specify the effort: `low`, `medium`, `high`, or `max`.
Default is **`high`**.

- **`low`**: shallow scan for high-impact correctness bugs, broken invariants,
  and leftover debug clutter. 1 reviewer; runs no synthesis.
- **`medium`**: thorough audit of correctness, edge cases, project guidelines,
  and simplification. 2 parallel reviewers with complementary lenses; runs
  no synthesis.
- **`high`** (default): deep audit across all 8 pillars below. 4 parallel
  reviewers, each owning 2 pillars, plus a synthesis pass over their reports
  (4 lenses plus synthesis in a full round).
- **`max`**: exhaustive audit, one reviewer per pillar (8 parallel), with one
  synthesis reviewer reconciling overlaps before you see the report (8 lenses
  plus synthesis in a full round).

The chosen effort is **fixed for the entire loop** except for the
user-approved quiet-round step-down below. Effort sets the review depth
per pillar and the full-round fan-out; it never escalates, and it never
de-escalates except through that step-down. Coverage, however, narrows
between rounds: round 1 always runs every lens, later rounds rerun only
the dirty set from the previous round (section 5, steps 1 and 7), and
the loop finishes only after a full round goes clean or nitpicks-only,
running a full confirmation round after every clean or nitpicks-only
narrowed round. An unknown argument
counts as no effort given: use the default and say so.

Choose the effort from the diff, not from habit: unfamiliar code, large
diffs, or security-sensitive areas earn `max`; small follow-ups on a
recently reviewed diff do fine at `low` or `medium`. When the
quiet-round streak reaches three, propose dropping one level to the user
rather than burning rounds at this effort. Score every round against the
streak exactly one way:
- A full round (any round that ran every lens per step 7: round 1,
  confirmation rounds, and subset-scheduled rounds that ran every
  lens) with every lens reported, at most one finding, and none above
  `quality` (no `bug`, `correctness`, or `convention` findings)
  extends the streak by one.
- A full round with zero reports received breaks the streak.
- A full round with more than one finding, or any finding above
  `quality`, breaks the streak, whether or not a lens is missing.
- A full round with a missing lens, at least one report received, at
  most one finding, and none above `quality` neither counts nor
  breaks.
- A subset round that ran fewer lenses never counts; it breaks the
  streak on zero reports received, more than one finding, or any
  finding above `quality`; a subset round with reports received, at
  most one finding, and none above `quality` (quiet) neither counts
  nor breaks.
Continue at the lower effort only with explicit approval; on approval
first apply steps 3-5 to any actionable findings still pending from the
qualifying rounds, then reset the quiet-round streak to zero (the next
proposal needs three qualifying full rounds all run at the new effort),
discard only the lens mapping (carrying the fixed locations as
must-recheck), and run the next round full at the new effort (the old
lens numbers do not map onto the new partition).

When your runtime caps concurrent subagents, run the round's reviewers in
waves inside the same round. The round's coverage stays fixed; only the scheduling bends.

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
rounds. Stop with a status report if the cap hits with a non-empty dirty
set or a confirmation still owed (step 7).

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

Scope the round's lenses before spawning. Round 1 and every full
confirmation round run every lens above. Any other round reruns only the
dirty set carried from the previous round (step 7): the lenses that
reported at least one actionable finding (any severity except `nitpick`),
plus any sitting-out lens flagged out of scope, plus any lens that
failed to report. Any other lens sits out; its pillars re-enter scope in
the next full confirmation round. Synthesis, when the effort calls for
it, covers only the running lenses' reports, and runs only when two or
more reports were received this round; with zero or one report skip
synthesis and classify directly (a single report needs no
reconciliation). When every running lens reported NO FINDINGS, skip
spawning a synthesis reviewer and classify from the reports directly.
If the dirty set holds more than half of a full round's lenses (compare
lens counts; synthesis is not a lens and is not counted), skip the
subset round and run a full round directly; a Clean or Nitpicks Only
result there with every lens reported finishes per step 2. Cancel or terminate any stalled reviewer before invoking synthesis. A synthesis subagent gets a progress file
(`<progress_dir>/r<N>-synthesis.progress`) under the same stall rule with
one replacement at `<progress_dir>/r<N>-synthesis-retry1.progress`
(created empty before spawning; watch the new file, never the old;
suffix the replacement task name `-retry1`; fresh 15 plus 5 window from
its own spawn); if it also stalls, cancel or terminate it (if the
runtime cannot cancel, note `uncancellable, ignored if it later
reports`) and present the unreconciled reports with
a Coverage note instead of blocking. The synthesis brief carries the same
redact-at-write-time rule as pillar reviewers: write
`<REDACTED_SECRET>` in place of every secret, token, or
credential-bearing argument, including inside the command name; never
paste unredacted credentials into the progress file.

Use your runtime's row. Every reviewer in the round reports before you
classify anything. If a reviewer has not reported within the runtime
default timeout, re-prompt it once; if still silent, cancel or terminate the
subagent if your runtime supports it, proceed with the reports in hand, note
the missing lens in the round summary, and let that lens rejoin the dirty
set next round (step 7).

The heartbeat stall rule below governs whenever progress files exist; the
runtime-timeout sentence above applies only when they do not (sequential
fallback, or progress setup failed) or as an outer bound when the runtime
drops the reviewer first. The one re-prompt and the one heartbeat nudge
are the same single nudge, not two. A runtime drop consumes that single
nudge: cancel any remnant, spawn one replacement immediately with no
grace wait on the dropped original, exactly as the stall path below
specifies (fresh empty retry1 file created before spawning, fresh 15
minute window plus one 5 minute grace counted from the replacement's own
spawn, task name suffixed `-retry1`). The runtime bound then caps the replacement
too: if the runtime kills the replacement first, proceed with no second
replacement.

<!-- Mirrored with skills/agent-review-report/SKILL.md: keep stall timings and replacement flow in sync; only the missing-lens destination (round summary plus dirty set here, report header there) and the per-round r<N>- retry path prefix (multi-round here, single round there) differ. -->
Stall detection runs on the progress files from the heartbeat rule below,
not on the runtime roster alone: a reviewer counts as stalled when its
progress file shows no new line for 15 minutes (counted from spawn or from
its last line), even when the runtime still lists it as running. On a
stalled reviewer, message it once asking for an immediate heartbeat line;
if the file is still silent 5 minutes later, cancel or terminate it and
spawn one replacement reviewer for the same lens with a fresh empty
progress file at `<progress_dir>/r<N>-<lens>-retry1.progress` (created
empty before spawning) and the same brief except for the new progress
path. Watch the new file for the replacement stall window, never the
old file. Suffix the replacement task name on every runtime (for
example `<name>-retry1`), so the dead worker and its replacement never
share a roster entry. The replacement's stall window is counted from its
own spawn: one fresh 15 minute window plus one 5 minute grace. If the
original stalls but its replacement reports, evaluate the lens from the
replacement's report and ignore any late report from the original; if
the original cannot be cancelled, note `uncancellable, ignored if it
later reports`. If the replacement also stalls, cancel or terminate it (if the runtime cannot cancel, note `uncancellable, ignored if it later reports`) and then proceed with the reports
in hand, note the missing lens in the round summary, and let that lens
rejoin the dirty set next round (step 7). Never let a silent reviewer hold
the round open past the original window plus grace plus the replacement
window plus grace.

<!-- Mirrored with skills/agent-review-report/SKILL.md: keep runtime rows in sync; intended differences only: collect verbs (classifying here, synthesizing there) and the Codex example task name. -->
| Runtime | How to spawn one reviewer per lens | How to collect |
|---|---|---|
| Muse | `subagent_spawn`, one child per reviewer in a single fan-out | `subagent_wait` on every child before classifying |
| Claude Code | `Task` tool, one call per reviewer, all calls issued together in a single block | every call returns its report; proceed only when all have returned |
| Codex | `spawn_agent` collaboration subagents; check `list_agents` first and never disturb unrelated agents; unique task names per round (for example `review_r3_correctness`) | wait for every reviewer in the round |
| Antigravity/Gemini | `invoke_subagent` with `TypeName` self or research and a distinct `Role` per reviewer | the call blocks until every reviewer in the round has reported; proceed only when all reports are in |
| Any other runtime | Sequential fallback: run one review pass per lens yourself, re-reading the diff fresh for each pass so earlier passes never narrow later ones | all passes complete before classifying |

<!-- Mirrored with skills/agent-review-report/SKILL.md: keep reviewer prompt bullets in sync; intended differences only: round-scope bullet, loop-only bullets-filed bullet, heartbeat naming/prefix, diff section ref plus PR drift line, guidance base-pillars ref. -->
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
- The round scope: the lenses running this round and the ones sitting out
  as clean. The reviewer audits the current filtered diff against its own
  pillars only, but flags a severe hazard clearly owned by a sitting-out
  lens in one line shaped `FLAG | lens <n> | file_path:line_number |
  one-line hazard`, so that lens rejoins the dirty set next round instead
  of waiting for confirmation. Out-of-scope flags are routing signals, not
  findings: they carry no severity and never change the round
  classification. They enter the dirty set defined in step 7; out of an
  Actionable round this widens next round's scope, while on an otherwise
  Clean or Nitpicks Only subset round the next round is a full
  confirmation round anyway (step 2), so the flag adds no further scope.
  In a full round no lens sits out, so no flag should arise; if one does,
  resolve it as reviewer disagreement (step 2) against the code before
  classifying: a confirmed hazard counts as an actionable finding from
  the owning lens.
- A read-only rule: reviewers report findings and edit nothing.
- An execution rule: behavior claims must be checked by running the repo's
  own tests or a minimal reproduction, quoted as command plus result. A
  claim that a test pins a behavior must be proven non-vacuous: show the
  test fails with the behavior present without the guard; for fixes with
  no guard to remove, replicate the old and new logic in a scratch probe
  outside the repo and show the old fails while the new passes. Reading alone is not evidence for behavior.
- Exact paths and bounded search: give the absolute path of every file the
  reviewer must read (diff, pillars, learnings files, repo guidance), so
  nothing needs locating. The reviewer must not run unbounded filesystem
  scans (`find /`, `ls -R` from the filesystem root, unscoped recursive
  greps) to locate them; scope every search to the repository or worktree.
  An unbounded scan parks the reviewer behind a result it never needs and
  stalls the whole round.
- A progress heartbeat: once per loop run, before the first spawn,
  create one run-unique progress directory with `progress_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-review-loop.XXXXXX")"`
  (one directory per loop run, so concurrent runs never share it) and
  print its path. Before each round's spawn, create one fresh empty
  progress file per reviewer in that round
  (`<progress_dir>/r<N>-<lens>.progress`, where `<lens>` is the
  reviewer number, for example `reviewer1`); when it already exists,
  refuse and recreate when it is a symlink or not a regular file: `rm -f
  "$path"` then `: > "$path"` immediately in the same step before
  spawning; otherwise truncate a validated regular file (`: > "$path"`);
  never open for write before the symlink test passes; and pass its path
  in the brief. Record
  each reviewer's spawn timestamp at spawn by first applying the same
  symlink refuse-and-recreate to `<progress_dir>/spawns.log` (`[ -L ] ||
  [ ! -f ]` means `rm -f` then `: >` before appending), then appending
  one `spawned <id> <ISO8601>` line per spawn (originals, `-retry1`
  replacements, synthesis, and fix-check attempts; `<id>` is the
  progress-file stem, for example `r3-reviewer2`, `r3-reviewer2-retry1`,
  `r3-synthesis`, `r3-fixcheck-attempt2`,
  `r3-fixcheck-reverify1-attempt1`) to `<progress_dir>/spawns.log`
  (read it when adjudicating a silent file); a reviewer not yet spawned
  (a later wave) is never stalled regardless of file age, and silence
  is measured from spawn, never from file creation time. The reviewer
  appends one timestamped line per step (brief read, guidance and
  pillars and learnings reads, diff read, each test or probe command
  started and finished, verdict written) and one line every 10 minutes
  regardless of activity, so no silent stretch ever reaches the 15
  minute stall window. Name each probe command in heartbeat lines with
  secrets redacted at write time (write `<REDACTED_SECRET>` in place of
  every secret, token, or credential-bearing argument, including inside
  the command name); never paste unredacted credentials into them. These files
  drive the stall rule above and let the human watch the round with
  `tail -f "$progress_dir"/r<N>-*.progress`. Never delete a path that
  is not inside `${TMPDIR:-/tmp}` under an `agent-review-loop.` or
  `agent-review-loop-diff.` prefix (canonicalized, symlinks resolved);
  refuse and report instead. Spell the check once:
  `tmpcanon=$(realpath "${TMPDIR:-/tmp}" 2>/dev/null || readlink -f
  "${TMPDIR:-/tmp}")` and `real=$(realpath "$path" 2>/dev/null ||
  readlink -f "$path")`, then require `$real` to start with
  `$tmpcanon/agent-review-loop.` or `$tmpcanon/agent-review-loop-diff.`.
- The finding format: `SEVERITY | file_path:line_number | one-line
  description | why it matters`, with `SEVERITY` in `bug`, `correctness`,
  `convention`, `quality`, or `nitpick`. Every non-nitpick needs a hazard
  explanation and a concrete fix (before and after code), not a generic
  summary. A reviewer with nothing to report returns exactly `NO FINDINGS`.

Merge and de-duplicate reports by `file_path:line_number` plus underlying
defect before classifying. When a non-nitpick finding names a changed area
that falls outside every lens's step 7 assignment for the round (a coverage
gap, not a de-dup candidate), the reporting lens keeps it: that lens is
already dirty through this finding, and re-runs with the area added to
its assignment next round; the round summary notes the gap. A synthesis
finding inherits its source lens for this rule.

### Step 2: Classify findings and check the stop condition

- **No reports**: no reviewer in the round reported. Skip fixes (step 3),
  the fix check (step 4), and the verification gate (step 5); still run
  the round summary with its Coverage entry and file the round learnings
  (step 6, mandatory) before advancing; the next round narrows to the
  missing lenses (step 7). Never classify an empty round as Clean.
- **Clean**: every reporting reviewer in the round returned `NO FINDINGS`.
- **Nitpicks Only**: every finding has `nitpick` severity (cosmetic
  formatting, doc phrasing, or trivial preferences only).
- **Actionable**: anything else (correctness risks, safety hazards,
  unbounded waits, leaks, contract drift). A missing lens never changes
  the classification by itself; it routes via the missing-lens branches
  below and the dirty set in step 7.

If **Actionable**: apply the fixes (step 3), then the fix check (step 4)
and verification gate (step 5) as usual; the next round narrows to the
dirty lenses (step 7).

If **Clean** or **Nitpicks Only** after a subset round: the narrowed
lenses are clean, but the sitting-out pillars have not been re-checked
against the latest fixes, so run one full confirmation round next (all
lenses at the loop's effort) instead of finishing.

If **Clean** or **Nitpicks Only** after a full round (round 1, a
confirmation round, or any round that ran every lens per step 7) in
which every lens reported: apply safe nitpicks from any round in one
final pass, run
the step 4 fix check on those edits (a main-agent direct check
suffices), then the full verification gate, the final pillar sweep
(section 6), and proceed to Finishing Up. A subset-scheduled round that
ran every lens needs no confirmation.

If **Clean** or **Nitpicks Only** after a full round with a missing
lens: the next round narrows to the missing lenses (step 7); a narrowed
follow-up that goes clean or nitpicks-only still owes confirmation per
the subset rule.

Treat reviewer disagreement as signal, not noise: if two reviewers
contradict each other, resolve the conflict against the code before fixing.

### Step 3: Apply fixes

Make precise, focused edits for every actionable item with your
environment's file editing tools. Keep each fix minimal and
behavior-scoped; do not refactor around a finding. If a fix is large or
structurally risky (broad refactor, API change, control flow with blast
radius), stop and ask the user before applying it. The stop report states
the finding and the proposed fix, with secrets redacted per the redaction
invariant (`<REDACTED_SECRET>`, never verbatim credentials) in that prose
as well as in the quoted heartbeat lines; file the round learnings before
stopping; retain the scratch diff and the progress directory while
awaiting the user; on a go-ahead apply the fix and continue at the fix
check, otherwise append a terminal status (the five contents defined at
the step 7 cap-stop), quote each missing lens's last progress line (same
redaction and empty/missing rules as Finishing Up step 3) into the stop
report, then run Finishing Up step 3.

### Step 4: Fix check (targeted re-review)

Before spending another review round, confirm the step 3 edits hold. Scope is only
the changed hunks plus their immediate callers and tests: one reviewer at
`low`, or the main agent directly when the fix is small. A fix-check
reviewer subagent gets a progress file
(`<progress_dir>/r<N>-fixcheck-attempt<A>.progress` on the first
invocation in a round, N the round number and A the attempt number
starting at 1, created empty before spawning; a re-verification
invocation from step 5 uses
`<progress_dir>/r<N>-fixcheck-reverify<V>-attempt<A>.progress`, V
counting this round's re-verifications from 1, so no two invocations
share attempt stems) under the same 15 plus 5 stall rule with
one replacement at the same stem plus `-retry1`
(created empty before spawning; watch the new file, never the old;
suffix the replacement task name `-retry1`; fresh 15 plus 5 window from
its spawn); when the original stalls, cancel or terminate it first: if
it cannot be cancelled, spawn no replacement, since a live mutator
leaves the tree untrusted, and instead treat the fix check as failed
(file the round learnings, retain the scratch diff, the progress
directory, and the snapshots, and stop and ask the user per the
regression-stop rule below, stating `fix check abandoned: uncancellable
original on attempt <A>` in place of a regression). Otherwise reconcile
the tree from the
original's snapshot directory when one exists (restore, verify
byte-identical; failures follow the restore-unverifiable stop rule
below); since the snapshot precedes any revert, an attempt that left no
snapshots left the tree untouched. If the replacement then reports,
evaluate the attempt from the replacement's report and ignore any late
report from the original; if the replacement also stalls, cancel or
terminate it, and if it cannot be cancelled, stop with no further
attempts (file, retain, ask per the regression-stop rule below, stating
`fix check abandoned: uncancellable replacement on attempt <A>` in
place of a regression);
otherwise treat the attempt as failed and consume one of the 3 attempts
without advancing to the verification gate: if attempts remain, first
reconcile the tree from the replacement's snapshot directory when one
exists (same restore-and-verify), then re-run the fix check as the
next attempt with a fresh file; if the third attempt fails or stalls,
reconcile the tree from the latest snapshot directory when one exists
(the replacement's when one exists, else the original's), then stop and
ask the user per the regression-stop rule below. Never proceed to the verification gate or a new review round
on a stalled (unreported) fix check. The fix-check brief carries the same
redact-at-write-time rule as pillar reviewers: write
`<REDACTED_SECRET>` in place of every secret, token, or
credential-bearing argument, including inside the command name; never
paste unredacted credentials into the progress file. Check three
things: each fix addresses its finding; the fix broke none of its own
preconditions (fast paths that bypass the fixed code, no-op contracts,
error mappings); every new or changed test is non-vacuous. The fix-check
subagent may temporarily revert hunks for this proof only (never commit
the reverted state): first snapshot the touched files under
`<progress_dir>/snapshots/<stem>/`, `<stem>` the attempt's own
progress-file stem (run-unique through the progress directory, and
distinct per invocation and attempt), creating the directory with
`mkdir -p -m 700` so no other user reads the copies; then revert, run
the test, restore immediately, then verify byte-identical restore (for
example `cmp` the restored files against the snapshots) before any
other step; on verified restore delete the stem's snapshot directory;
if restore cannot be verified, file
the round learnings, retain the scratch diff, the progress directory,
and the snapshots, and stop and ask the user with the `cmp` output
redacted; on a go-ahead restore from the snapshots, verify
byte-identical, delete them, and continue at the fix check, otherwise append a
terminal status (the five contents defined at the step 7 cap-stop),
quote each missing lens's last progress line (same redaction and
empty/missing rules as Finishing Up step 3) into the stop report, then
run Finishing Up step 3. A main-agent direct check follows
the same snapshot-revert-restore-verify sequence. When the check finds a regression, fix it and repeat this
step (at most 3 attempts total). If the third attempt still shows a
regression, stop and ask the user how to proceed; never launch another
review round on a fix known to be broken. The stop report states the
failing fix, the attempt number, and the observed regression, or, when
the third attempt stalled, `fix check stalled on attempt 3` plus the last
lines of the third attempt's own progress file and its `-retry1` file (or
`no heartbeat lines` when a file exists but is empty, or `no progress
file` when no file exists); redact
secrets per the redaction invariant (`<REDACTED_SECRET>`, never verbatim
credentials) in that prose as well as in the quoted heartbeat lines. File the
round learnings before stopping; retain the scratch diff and the progress
directory while awaiting the user; on a go-ahead resume at the
verification gate, otherwise append a terminal status (the five contents
defined at the step 7 cap-stop), quote each missing lens's last progress line
(same redaction and empty/missing rules as Finishing Up step 3) into the
stop report, then run Finishing Up step 3.

### Step 5: Verification gate

Discover and run the repository's own gates; never substitute generic
checks. Read the CI workflows and project docs first, then at minimum:

- Format gate clean (whatever CI enforces).
- Static analysis / linters clean for every affected language.
- The full test files or packages covering the touched areas, run
  unmodified. A red test after your change is a requirement, not a stale
  artifact: fix the change, never weaken or skip the test.
- The punctuation invariant holds in everything you wrote or edited.

On any gate failure: fix the change (never weaken or skip the test),
re-run one full step 4 fix-check invocation (with its own up-to-3
attempt budget, on the `-reverify<V>` stems from step 4) and then this
gate; at most 2 re-verifications per
round, else file the round learnings, retain the scratch diff and the
progress directory, and stop and ask the user with the failing gate
output redacted; on a go-ahead resume at this gate, otherwise append a
terminal status (the five contents defined at the step 7 cap-stop),
quote each missing lens's last progress line (same redaction and
empty/missing rules as Finishing Up step 3) into the stop report, then
run Finishing Up step 3; never advance to step 6/7 with a red gate.

### Step 6: Round summary and learning capture

Report between rounds, briefly:

- **Round `n` findings**: issues, warnings, suggestions (one line each).
- **Scope next**: dirty lenses rerunning next round and lenses sitting
  out, or `full confirmation round` when step 2 owes one, or `done`.
- **Coverage**: `full` only when every running lens this round reported
  with no stall (sitting-out lenses are out of scope, neither reported
  nor missing) and synthesis (when spawned) reported with no stall. Otherwise
  list each stalled, missing, or recovered lens: lens; pillars covered
  (`recovered after nudge`, `replacement reported`) vs uncovered
  (`replacement also stalled`, `replaced then capped (outer bound)`,
  `not replaced`); last heartbeat timestamp with the operative file's
  last line quoted, secrets redacted per the redaction invariant
  (original file for recovered/not-replaced, replacement file for
  replacement-reported/also-stalled/capped, both when both have lines;
  `no heartbeat lines` when the operative file exists but is empty,
  `no progress file` when no file exists under sequential fallback or
  failed progress setup); outcome as one of the five above, plus, when
  synthesis was spawned and stalled or was replaced, one synthesis row:
  `synthesis`, covered vs uncovered per the same five outcomes, operative
  file per the same file rules. A recovered
  stall stays listed; it never collapses back to `full`.
- **Fixes applied**: files and what changed.
- **Verification status**: gates run and their results.
- **Learnings filed**: pillar bullets added or refined this round (with
  canonical pillar numbers and titles), or `none` with one line on why the
  round taught nothing durable.

Then file this round's learnings immediately, per section 6. Do not batch
them for loop end: the next round's reviewers read them (step 1), so each
round reviews against what the previous rounds learned. Filing is a mandatory
step of the round: you must use your file editing tool to write or refine the
bullets in the target refinements file on disk before advancing. A round is
not complete until its learnings are written to disk or explicitly skipped
as non-novel.

### Step 7: Advance

Carry the dirty set forward: the lenses with at least one actionable
finding in round `n`, plus any sitting-out lens flagged out of scope
this round, plus any lens that failed to report in round `n` (a missing
report never counts as clean). Increment `n` and loop back to step 1,
where the next round reruns only those lenses, except that a clean
or nitpicks-only subset round is followed by one full confirmation
round (step 2). A
round that runs every lens counts as full even when every lens was
dirty. The 10 round cap counts subset and confirmation rounds together;
hitting it with a non-empty dirty set, or with a confirmation still
owed, stops the loop with a status report. The cap-stop still runs
Finishing Up step 3 (delete the scratch diff and the run's progress
directory after quoting each missing lens's last progress line, with
secrets redacted per the redaction invariant (or `no heartbeat lines`
when the operative file exists but is empty, or `no progress file` when
no file exists), into the status report). The status
report states the dirty set (marking which lenses are missing vs
actionable), whether a confirmation round is still owed, the step 6
Coverage entry for the final round, the last verification gate result
(or `never ran` when no gate ran), and that the diff is not confirmed
clean. Coverage-only retry limit: when the dirty set from step 7
(renamed here as the outstanding set) is non-empty and identical across
two rounds in a row (full or subset), consists solely of lenses that
failed to report with no flagged lens in either set, and no lens
reported an actionable finding in either round, stop with the same
status report early (same contents, and the same Finishing Up step 3
quote-then-delete) instead of consuming the cap; a missing lens still
never counts as clean. Only a round with an actionable finding, or a
report from a previously outstanding lens, breaks the tripwire streak.

## 6. Pillar Update (Shared Learnings, Multi-Agent Safe)

The loop earns its keep twice: once in the fixed diff, once in the next
review. File learnings after every round (step 6), not at loop end: each
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

<!-- Mirrored with skills/agent-review-report/SKILL.md: keep pillar filing rules in sync; intended differences only: round vs review wording and the loop-only `Learnings filed: none` report line. -->
### How to Update the Refinements File Correctly

Follow this exact sequence whenever filing learnings:

1. **Fresh re-read**: View the target file immediately before editing, in the
   same step as the write. Never edit from a copy loaded at round start;
   another loop may have filed bullets in the interim.
2. **Automatic timestamped backup and accumulation check**:
   - Before modifying the file, record the snapshot path and create a timestamped backup snapshot:
     ```bash
     backup_dir="$(dirname "$target")/backups"
     backup_snapshot=""
     if [ -f "$target" ]; then
       mkdir -p "$backup_dir" || { echo "ERROR: failed to create backup directory: $backup_dir" >&2; exit 1; }
       backup_snapshot="$backup_dir/review-refinements-$(date "+%Y%m%d-%H%M%S").md"
       cp -p "$target" "$backup_snapshot" || { echo "ERROR: failed to snapshot $target to $backup_snapshot" >&2; exit 1; }
     fi
     ```
   - Check if backups accumulate: if `[ -d "$backup_dir" ]`, count the backup files in `"$backup_dir"`
     (for example, `ls -1 "$backup_dir"/review-refinements-*.md 2>/dev/null | wc -l`).
     If more than 5 backups exist, ask the user in chat whether they would like
     to prune older backups (keeping the latest 5). Never prune or delete
     backups without explicit user confirmation.
3. **Classify under the exact canonical pillar**: Match the lesson to one of
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
4. **Add or merge (living document evolution)**: Read existing bullets under
   that pillar's heading. Incorporate all actionable suggestions, optimizations,
   and durable failure modes without arbitrary numerical quotas. If the round
   surfaced nothing durable or novel beyond what is already codified, leave the
   file untouched and report `Learnings filed: none`. Otherwise, for each
   suggestion, decide whether to merge it into an existing bullet or add it as
   a new bullet:
   - **Merge**: Actively rewrite existing bullets into broader, higher-level
     principles that synthesize prior lessons and new findings into a cohesive
     rule.
   - **Add**: If a suggestion represents an entirely distinct concern that
     cannot be naturally merged, add it as a new bullet, written at a general
     cross-stack level.
5. **Format the bullet**: Each bullet must adhere to the exact structure:
   `- **Title**: Trigger condition (when doing X): hazard or failure mode (Y occurs); fix shape and verification guidance (fix by doing Z, and verify via W).`
   - Single bullet starting with `- **Title**:`.
   - Title in Title Case (2 to 5 words).
   - Domain-neutral trigger, hazard, and fix shape.
   - Tool-agnostic: never name an agent, model, runtime, or assistant tool.
   - Zero attribution: no signatures, author tags, dates, or loop IDs.
   - Punctuation invariants: zero em dashes (U+2014) or `--` / spaced hyphens
     as punctuation lookalikes. Use standard ASCII punctuation (colons, commas,
     semicolons, parentheses, periods).
6. **Surgical chunk editing and total cleanup**:
   - Use surgical chunk replacement tools (never overwrite the entire file).
     Edit only the lines within the specific `### Pillar N:` section being
     modified.
   - If merging with an existing bullet, rewrite it in place.
   - If adding a new bullet, insert it directly under the appropriate
     `### Pillar N:` heading (below `<!-- Loops append bullets here. -->` or
     after existing bullets in that section, strictly before the next
     `### Pillar` heading).
   - **Clean up total bullets**: Do not just keep adding new bullets without
     cleaning up the total bullets after adding them. After adding or merging,
     review all bullets under that pillar as a whole: clean them up, reorganize
     them for clarity, consolidate any overlapping themes, tighten phrasing,
     and ensure the entire pillar remains concise, organized, and evolved
     over time.
   - Never append bullets at the end of the file outside a pillar section.
7. **Immediate read-back and invariant verification**:
   - View the modified lines with a file viewing tool to confirm correct
     placement, valid markdown, and preserved pillar structure.
   - Verify that all 8 `### Pillar` headings remain intact byte-for-byte
     (`grep -c '^### Pillar' "$target"` must equal 8). If verification fails,
     immediately roll back structural changes: if a backup snapshot was created
     in step 2, restore from it (`cp -p "$backup_snapshot" "$target"`); if
     `$target` was newly created in this cycle, remove it (`rm -f "$target"`),
     before retrying or reporting failure.

## 7. Finishing Up

1. **Cumulative summary**: total rounds, every issue/warning/optimization
   addressed across rounds, verification results, and which pillar bullets
   were added or refined per round (with pillar numbers).
2. **Approval for commit and push**: do not commit or push on your own.
   Present the proposed commit message in the repo's convention and ask for
   explicit confirmation first.
3. **Scratch diff cleanup**: always clean up the scratch diff file created in
   section 4 (first re-apply the step 1 prefix check on the canonicalized
   path and refuse on mismatch, then `rm -f "${diff_file:?}"`) and the
   run's progress directory
   (first re-apply the step 1 prefix check on the canonicalized path and
   refuse on mismatch, then `rm -rf "${progress_dir:?}"`), after quoting
   each missing lens's last progress line, with secrets redacted per the
   redaction invariant (or `no heartbeat lines` when the operative file
   exists but is empty, or `no progress file` when no file exists), into
   the cumulative summary.
