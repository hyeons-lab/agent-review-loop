---
name: agent-review-report
description: Run one exhaustive max-effort review (8 pillar reviewers plus synthesis) over the working diff or a target PR, present the findings to the user, and post them to the PR only with explicit approval. Works in Muse, Claude Code, Codex, and Antigravity/Gemini.
---

# Max Review and Report (Single Pass, Read Only)

Run one exhaustive review at `max` effort over the working diff or a
target PR, then report. This skill never edits code, never commits,
never pushes, and never posts to a PR on its own. Every finding goes to
the user in chat; PR posting happens only after the user explicitly
approves it for that run.

This skill runs in Muse, Claude Code, Codex, and Antigravity/Gemini.
Section 4 maps each runtime to its native subagent mechanism. Use the
row that matches your runtime. When your runtime offers no subagent
tool at all, use the sequential fallback in that same table.

## 0. Core Invariants

1. **Zero AI attribution**: never attribute yourself or any AI assistant in
   reports, PR comments, code quotes, or prose.
2. **Punctuation**: never write an em dash (U+2014), and never use `--`
   or spaced hyphens as punctuation in prose. `--` stays allowed in
   command flags, code, and quoted output. In prose, use colons, commas,
   semicolons, parentheses, or separate sentences.
3. **Read only**: report findings and edit nothing. No file edits, no
   commits, no pushes, no review thread resolves, no CI cancellations.
   Propose concrete fixes in the report; do not apply them.
4. **No unapproved posts**: never comment on a PR without explicit human
   approval in this session for this report. Presenting findings in chat
   is not approval to post them.
5. **Credential redaction**: ensure secrets, API keys, passwords, and private
   tokens are redacted from reports and PR comments; use placeholders like
   `<REDACTED_SECRET>` instead.

## 1. Review Target

The skill takes an optional target argument:

- **No argument**: review the **working-tree diff** (staged plus
  unstaged). When the tree is clean but the branch is ahead of its base,
  review the **branch diff** (`git diff <base>...HEAD`, base from the
  merge-base with the default branch). Inside a worktree, run every
  `git` command with `git -C <worktree>`. Filter out lockfiles, generated
  code, and binary artifacts into a scratch file:
  ```bash
  if git diff --quiet HEAD -- .; then
    base="$(git merge-base origin/main HEAD 2>/dev/null || git merge-base main HEAD 2>/dev/null || echo "origin/main")"
    diff_target="${base}...HEAD"
  else
    diff_target="HEAD"
  fi

  diff_file="$(mktemp "${TMPDIR:-/tmp}/agent-review-report-diff.XXXXXX")"
  git --no-pager diff "${diff_target}" -- . \
    ':!**/*.lock' ':!**/Cargo.lock' ':!**/package-lock.json' ':!**/pnpm-lock.yaml' ':!**/uv.lock' \
    ':!**/target/**' ':!**/dist/**' ':!**/build/**' ':!**/node_modules/**' \
    ':!**/*.onnx*' ':!**/*.gguf' ':!**/*.wasm' ':!**/*.dylib' ':!**/*.so' ':!**/*.dll' \
    ':!**/generated/**' ':!devlog/**' ':!docs/**' > "$diff_file"
  ```
- **PR number or URL**: review that PR's diff. `gh` and `jq` must be on
  `PATH`. When they are installed but not found (for example a macOS
  Homebrew install outside the inherited `PATH`), prefix the commands
  below with `export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"`
  (Apple Silicon, then Intel Mac; Linuxbrew users add
  `$(brew --prefix)/bin` instead). Resolve the input to a canonical
  numeric PR ID, record the head SHA the review covers, and fetch the
  diff with:
  ```bash
  pr_number="$(gh pr view "$pr_input" --json number --jq .number)" || { echo "ERROR: gh pr view failed for $pr_input; check PR number or URL" >&2; exit 1; }
  [[ "$pr_number" =~ ^[0-9]+$ ]] || { echo "ERROR: resolved PR number is non-numeric: $pr_number" >&2; exit 1; }
  diff_file="$(mktemp "${TMPDIR:-/tmp}/agent-review-report-diff.XXXXXX")"
  sha_before=$(gh pr view "$pr_number" --json headRefOid --jq .headRefOid) || { echo "ERROR: gh pr view failed for PR $pr_number; aborting, head SHA unknown" >&2; rm -f "$diff_file"; exit 1; }
  [ -n "$sha_before" ] && [ "$sha_before" != "null" ] || { echo "ERROR: head SHA missing for PR $pr_number; aborting" >&2; rm -f "$diff_file"; exit 1; }
  gh pr diff "$pr_number" > "$diff_file" || { echo "ERROR: gh pr diff failed for PR $pr_number; aborting, diff not fetched" >&2; rm -f "$diff_file"; exit 1; }
  [ -s "$diff_file" ] || { echo "ERROR: empty diff for PR $pr_number; aborting rather than reviewing nothing" >&2; rm -f "$diff_file"; exit 1; }
  sha_after=$(gh pr view "$pr_number" --json headRefOid --jq .headRefOid) || { echo "ERROR: gh pr view failed for PR $pr_number; aborting, head SHA unknown" >&2; rm -f "$diff_file"; exit 1; }
  ```
  When `sha_before` and `sha_after` differ, a push landed mid-fetch:
  refetch once more (at most 3 attempts total, then report the drift
  and stop). Record the SHA that matches the kept diff. Abort the run
  when any fetch fails or the diff is empty; never present a report
  over a diff that was never fetched.

Save the filtered diff to a uniquely named scratch file under
`${TMPDIR:-/tmp}` (for example via `mktemp`) so concurrent runs never
share it and reviewers can inspect it without context truncation. Clean up the
scratch diff file when the report finishes (`rm -f "$diff_file"`). For a
PR target, apply the same exclusions by path when reading the fetched
diff. Never review a diff you have not read; never let a reviewer
report stand in for reading the changed code.

## 2. Review Criteria: Base Pillars Plus Shared Learnings

Two tiers, same contract in every runtime:

1. **Base pillars** (stable defaults): read the sibling
   `agent-review-loop` skill's
   `thematic-review-pillars.md`
   (`../agent-review-loop/thematic-review-pillars.md` relative to this
   skill's directory) when it is installed alongside this one. This
   skill never edits that file. When the sibling file is missing, audit
   against the 8 pillar titles quoted in section 4, and record
   `criteria: titles-only fallback (sibling
   thematic-review-pillars.md missing)` in the Reviewed scope header;
   when the sibling file is present, record `criteria: full base
   pillars`. Never present a titles-only review without that marker.
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

## 3. Pillar Stability

Review against the 8 pillars in section 4 by number, exactly as listed.
Never substitute a custom pillar set: shared learnings are filed by
pillar number, so a renamed set orphans every bullet and the next review
starts blind.

## 4. The Review Protocol (One Round, Max Fan-Out)

Run exactly one review round: 8 parallel reviewers, one per pillar. Only
after all 8 reports have returned (or timed out after one re-prompt), run one
synthesis reviewer that reconciles overlaps before you see the report. If all
reviewers reported NO FINDINGS, skip spawning a synthesis reviewer and present
NO FINDINGS directly. If a reviewer has timed out, cancel or terminate it
according to your runtime's lifecycle management before invoking synthesis.
Never spawn synthesis concurrently with the pillar reviewers. When your runtime
caps concurrent subagents, run the reviewers in waves inside the same round.
Coverage stays fixed; only the scheduling bends.

Each reviewer audits the filtered diff plus the surrounding source it
needs (callers, types, tests, configs) against its assigned pillar of
the **8 Canonical Thematic Pillars**:

1. Functional Correctness, Logic & Edge Cases
2. Security, Authentication & Input Sanitization
3. Concurrency, Asynchrony & Lifecycle Management
4. Error Handling, Resilience & Diagnostics
5. Interface Contracts, API Design & Compatibility
6. Performance, Resource Efficiency & Scalability
7. Code Simplification, Clean Architecture & Maintainability
8. Testing, Observability & Verification Invariants

Use your runtime's row. Every reviewer in the round reports before you
synthesize anything. If a reviewer has not reported within the runtime
default timeout, re-prompt it once; if still silent, cancel or terminate the
subagent if your runtime supports it, proceed with the reports in hand, note
the missing lens in the report header, and treat its pillars as uncovered.

<!-- Mirrored with skills/agent-review-loop/SKILL.md: keep runtime rows in sync. -->
| Runtime | How to spawn one reviewer per lens | How to collect |
|---|---|---|
| Muse | `subagent_spawn`, one child per reviewer in a single fan-out | `subagent_wait` on every child before synthesizing |
| Claude Code | `Task` tool, one call per reviewer, all calls issued together in a single block | every call returns its report; proceed only when all have returned |
| Codex | `spawn_agent` collaboration subagents; check `list_agents` first and never disturb unrelated agents; unique task names per round (for example `report_r1_correctness`) | wait for every reviewer in the round |
| Antigravity/Gemini | `invoke_subagent` with `TypeName` self or research and a distinct `Role` per reviewer | the call blocks until every reviewer in the round has reported; proceed only when all reports are in |
| Any other runtime | Sequential fallback: run one review pass per lens yourself, re-reading the diff fresh for each pass so earlier passes never narrow later ones | all passes complete before synthesizing |

<!-- Mirrored with skills/agent-review-loop/SKILL.md: keep reviewer prompt bullets in sync. -->
Every reviewer prompt must include:

- The scratch path of the filtered diff saved in section 1, plus its line
  count. The reviewer quotes both back in the report header, so a scope
  mismatch (stale diff, wrong worktree, drifted PR head) is visible
  before anything else. Embed the diff text only when it is small enough
  to fit comfortably.
- The instruction to read the repo's own guidance first (`AGENTS.md`,
  `CLAUDE.md`, `GEMINI.md`, `.editorconfig`, CI workflows), the base
  pillars (section 2, tier 1), and every shared learnings file that
  exists.
- A read-only rule: reviewers report findings and edit nothing.
- An execution rule: behavior claims must be checked by running the repo's
  own tests or a minimal reproduction, quoted as command plus result. A
  claim that a test pins a behavior must be proven non-vacuous: show the
  test fails with the behavior present without the guard. Reading alone
  is not evidence for behavior.
- The finding format: `SEVERITY | file_path:line_number | one-line
  description | why it matters`, with `SEVERITY` in `bug`, `correctness`,
  `convention`, `quality`, or `nitpick`. Every non-nitpick needs a hazard
  explanation and a concrete fix (before and after code), not a generic
  summary. A reviewer with nothing to report returns exactly `NO FINDINGS`.

Merge and de-duplicate reports by `file_path:line_number` plus underlying
defect before presenting. Treat reviewer disagreement as signal, not
noise: if two reviewers contradict each other, resolve the conflict
against the code before reporting.

## 5. Present the Findings

Always present the full report to the user in chat, ordered by severity
(`bug` first, `nitpick` last). The report leads with scope, then
findings:

1. **Reviewed scope**: working diff (plus base SHA when it is a branch
  diff) or PR number plus the head SHA the diff was fetched at, so a
  mid-run push shows as drift; plus the criteria marker from section 2
  (`criteria: full base pillars`, or the titles-only fallback marker).
2. **Findings**: every finding with severity, `file_path:line_number`,
  one-line description, hazard explanation, and concrete fix. Group
  duplicates once with all affected locations. When every reviewer
  returned `NO FINDINGS`, say so explicitly instead of padding the
  report.
3. **Suggested next step**: name the skill that fits what the user might
  want next (`agent-review-loop` to fix the diff in a loop,
  `address-pr-comments` once PR feedback lands). Suggest only; never
  invoke another skill unasked.

## 6. Optional PR Posting (PR Targets Only)

When the target was a PR, ask the user whether the presented findings
should also be posted to the PR. Ask after presenting the report, never
before, so the user approves the exact content they saw. On any answer
other than an explicit yes, post nothing and say the report stays local.

On explicit approval:

1. Render the presented report as one consolidated Markdown comment (same
   scope header and findings, no new claims beyond what was presented).
2. Write the body to a uniquely named scratch file and post it with an
   explicit target:
   ```bash
   comment_file="$(mktemp "${TMPDIR:-/tmp}/agent-review-report-comment.XXXXXX")"
   # ... render the presented report into "$comment_file" ...
   gh pr comment <pr_number> --body-file "$comment_file"
   rm -f "$comment_file"
   ```
3. Report the posted comment URL back to the user.

Never use the inline review or review thread APIs, never resolve
threads, and never post a second comment without a fresh approval.

## 7. Pillar Update (Shared Learnings, Multi-Agent Safe)

A report-only review still teaches: file at most 2 genuinely novel
bullets per run so later reviews catch what this one caught. Skip filing
when the round taught nothing durable.

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
   `### Pillar N:` headings (copy their exact titles from the base pillars
   file, or use the 8 canonical titles in Section 4 if the base pillars file
   is absent), then append.
4. Never write the legacy `~/.gemini/review-refinements.md` path. It is read
   only when `$REVIEW_REFINEMENTS_LEGACY=1` is set; all new writes go to
   canonical or repo-local.

Re-read the target file immediately before editing, in the same step as
the write. Never edit from the copy loaded at review start; another loop
may have filed bullets since. When a fresh read shows your lesson already
covered, subsume instead of duplicating.

<!-- Mirrored with skills/agent-review-loop/SKILL.md: keep pillar filing rules in sync. -->
### How to Update the Refinements File Correctly

Follow this exact sequence whenever filing learnings:

1. **Fresh re-read**: View the target file immediately before editing, in the
   same step as the write. Never edit from a copy loaded at review start;
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
   Every bullet filed in canonical must help across stacks and repositories;
   lessons specific to one repository belong in repo-local refinements.
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
     Never append bullets at the end of the file outside a pillar section.
6. **Immediate read-back**: View the modified lines with a file viewing tool
   to confirm correct placement, valid markdown, and preserved pillar structure.
7. **Stay bounded**: At most 2 new or refined bullets per run. If the review
   surfaced nothing durable or novel, leave the file untouched.

## 8. Finishing Up

Always clean up the scratch diff file created in section 1 (`rm -f "$diff_file"`).

