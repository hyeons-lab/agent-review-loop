---
name: address-pr-comments
description: Address PR review comments (human feedback and automated review bots) on a target PR, apply and validate the fixes, sync stacked PRs, and fold CI-caught misses back into the shared cross-agent review pillars used by agent-review-loop.
---

# Address PR Comments (Multi-Agent)

Autonomously address pull request review comments (human feedback and
automated review bots), apply and validate the fixes, synchronize stacked
PRs, and synthesize what CI caught into the shared review pillars so local
pre-merge review keeps getting stronger without growing an unbounded
checklist.

This skill runs in Muse, Claude Code, Codex, and Antigravity/Gemini. It
runs its `gh` and `git` commands directly and needs no subagents. It shares
the two-tier review criteria with `agent-review-loop`: the stable base
pillars plus the evolving shared learnings file.

## 0. Core Invariants

1. **Zero AI attribution**: never attribute yourself or any AI assistant in
   commits, PR descriptions, code comments, docstrings, or prose.
2. **Punctuation**: never write an em dash (U+2014), and never use `--`
   or spaced hyphens as punctuation in prose. `--` stays allowed in
   command flags, code, and quoted output. In prose, use colons, commas,
   semicolons, parentheses, or separate sentences.
3. **Commit and push rules**:
   - Follow the repository's own commit convention (repo docs win over any
     default; never add attribution or trailer lines).
   - Stage only the files you changed, never a broad add in a tree you did
     not clean.
   - Confirm the push destination with the user before the first push,
     unless this session already approved pushes for this PR workflow.
4. **Verification gate**: everything must compile, the repo's own format and
   static-analysis gates must be clean, and the relevant tests must pass
   before the fix commit is pushed.

## Workflow

```mermaid
flowchart TD
    A[Fetch PR comments & CI reviews] --> B[Triage & categorize feedback]
    B --> C[Apply code fixes in the worktree]
    C --> D[Run local format, lint & test checks]
    D --> E[Thematic synthesis: generalize the shared pillars]
    E --> F[Commit, cascade-rebase the stack & submit]
    F --> G[Cancel superseded CI runs & verify checks]
    G -->|"checks red, cycle < 3"| A
    G -->|"checks green"| H[Output summary]
    G -->|"checks red, cycle = 3"| I[Stop and report]
```

## Prerequisites

`gh` and `jq` must be on `PATH`. When they are installed but not found
(for example a macOS Homebrew install outside the inherited `PATH`),
prefix the commands below with
`export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"` (Apple Silicon,
then Intel Mac; Linuxbrew users add `$(brew --prefix)/bin` instead).

The skill takes a target PR number or URL (`<pr_input>`). When omitted,
use the open PR for the current branch and stop when there is not
exactly one. Run in a checkout of the PR's repository (or its worktree):
`gh` fills `{owner}` and `{repo}` in API paths from that checkout.
Section 1A resolves the input to a number once; use that number for
`<pr_number>` in every later snippet. If the work lives in a git
worktree, run every `git` command against it explicitly
(`git -C <worktree> ...`) rather than relying on `cd`.

---

## 1. Fetch & triage PR comments

On cycles after the first, re-read the shared refinements write target
(same fresh-read rule as section 3) before triaging, so this cycle audits
against lessons earlier cycles filed.

### A. Query the GitHub API for feedback

Retrieve inline review comments, submitted review summaries, and
top-level issue comments for the target PR. Resolve the input first,
then fetch:

```bash
# Resolve once: canonical number plus the triage SHA for the summary
gh pr view <pr_input> --json number,headRefOid --jq '"number: \(.number)", "triage_sha: \(.headRefOid)"' || { echo "ERROR: PR resolve failed; check the number or URL and gh auth"; exit 1; }

# Inline diff comments
gh api /repos/{owner}/{repo}/pulls/<pr_number>/comments > /tmp/pr-diff-comments.json || { echo "ERROR: diff-comment fetch failed; check the PR number and gh auth"; exit 1; }
jq -r '.[] | "DIFF [\(.id)] \(.path):\(.line) by \(.user.login):\n\(.body)\n"' /tmp/pr-diff-comments.json || { echo "ERROR: diff-comment render failed; check jq and the JSON payload"; exit 1; }

# Submitted review summaries (approve/changes-requested bodies: Copilot, humans)
gh api /repos/{owner}/{repo}/pulls/<pr_number>/reviews > /tmp/pr-reviews.json || { echo "ERROR: review fetch failed; check the PR number and gh auth"; exit 1; }
jq -r '.[] | "REVIEW [\(.id)] \(.state) by \(.user.login):\n\(.body)\n"' /tmp/pr-reviews.json || { echo "ERROR: review render failed; check jq and the JSON payload"; exit 1; }

# Top-level issue comments (review bots, humans)
gh api /repos/{owner}/{repo}/issues/<pr_number>/comments > /tmp/pr-issue-comments.json || { echo "ERROR: issue-comment fetch failed; check the PR number and gh auth"; exit 1; }
jq -r '.[] | "ISSUE [\(.id)] by \(.user.login):\n\(.body)\n"' /tmp/pr-issue-comments.json || { echo "ERROR: issue-comment render failed; check jq and the JSON payload"; exit 1; }
```

### B. Categorize the findings

File every finding under one of the 8 Core Thematic Pillars (titles are
exact; the sibling `agent-review-loop` skill's base pillars file defines
them):

1. Low-Level Safety, Alignment & Buffer Invariants
2. Concurrency, Cancellation & State Machine Lifecycles
3. Error Propagation, Diagnostics & No-Panic Invariants
4. Multiplatform Portability & Cross-Binding Drift
5. Numerical Robustness & Boundary Validation
6. Pipeline Completeness & Contract Faithfulness
7. Performance, SIMD & Resource Efficiency
8. Code Simplification, Cleanup & Complexity Reduction

Read the base pillars from the sibling `agent-review-loop` skill directory
when it is installed alongside this one
(`../agent-review-loop/thematic-review-pillars.md`); otherwise triage
against the titles above plus every shared learnings file that exists (see
section 3).

Treat bot feedback as unverified until checked against the *current*
worktree code: a bot often flags logic that was already refactored or is
already handled. Document each false positive with its technical reasoning
plus the command and output that disproves it, so the next reader need not
re-derive the check, instead of changing code to silence it.

---

## 2. Apply fixes & validate locally

1. **Implement the fixes** with file editing tools in the worktree. Keep
   each fix minimal and behavior-scoped. Every fix ships with a test or
   reproduction run quoted as command plus result; prove each new
   regression test non-vacuous by showing it fails with the fix reverted.
   Before any fix that is large or structurally risky (broad refactor, API
   or signature change, control flow that could ripple), stop and ask the
   user before applying it.
2. **Generated-code synchronization** (only when a checked-in generated
   surface changed): regenerate every derived artifact the repo checks in
   (bindings, clients, docs) with the repo's own commands and confirm the
   regeneration leaves a zero git diff.
3. **Format, lint, and tests**: discover and run the repository's own
   gates; never substitute generic checks. Read the CI workflows and
   project docs first, then at minimum run the format gate, the linters
   for every affected language, and the full test files or packages
   covering the touched areas, unmodified. Mirror whatever gate set CI
   actually runs; a doc or lint step that only CI runs costs a wasted CI
   cycle and a force-push.

---

## 3. Thematic synthesis: generalize the shared pillars

**The goal**: make the next local review catch what CI caught, while
keeping the shared learnings clean, structured, and bounded. Never append
an open-ended list of specific micro-checks.

File after every fix cycle, not once at the end: when a push comes back
red and the workflow loops back through fixes, each cycle's lesson goes in
immediately. Later cycles in the same run read what earlier cycles filed,
so the same class of miss is caught locally the second time.

When CI catches something local review missed, file the lesson in the
shared refinements file both skills read. Resolution order for reading
(the more specific file wins a direct conflict):

- `$REVIEW_REFINEMENTS_FILE` when set (explicit override).
- Repo-local `.agents/review-refinements.md` (project specific).
- Canonical `~/.agents/review-refinements.md` (default write target).
- Legacy `~/.gemini/review-refinements.md` (read only when
  `$REVIEW_REFINEMENTS_LEGACY=1` is set; skipped by default).

Pick the write target in order:

1. `$REVIEW_REFINEMENTS_FILE` when set: write there.
2. A repo-specific lesson (it names this repo's modules, crates, tools, CI
   jobs, or architectures): file it in the repo's own
   `.agents/review-refinements.md`, creating that file with the 8
   `### Pillar N:` headings when it does not exist yet. Do not commit the
   repo-local file on your own; include it only in a commit the user
   explicitly approved.
3. Otherwise the canonical `~/.agents/review-refinements.md`. Standing rule:
   every filed bullet must help a review in a different repo on a different
   stack; if it cannot be stated that generally, abstract it or file it
   repo-local. When it does not exist yet, create it with the 8
   `### Pillar N:` headings, then append.
4. Never write the legacy `~/.gemini/review-refinements.md` path. It is read
   only when `$REVIEW_REFINEMENTS_LEGACY=1` is set; all new writes go to
   canonical or repo-local.

Re-read the target file immediately before editing, in the same step as
the write. Never edit from a stale copy; another loop may have filed
bullets since.

Rules:

1. **Subsumption first**: if an existing bullet under a pillar already
   covers the lesson, refine that bullet instead of adding a sibling.
2. **Generalize**: write the principle the finding taught (trigger,
   hazard, fix shape), not the instance. One bullet must help a future
   review in a different file, and every bullet in canonical must help
   across stacks.
3. **Higher-order abstraction**: when several specific checks are
   variations of one concept, synthesize them into a single principle
   rather than filing each one.
4. **File under the right pillar**: match the finding to one of the 8
   `### Pillar N:` sections. Never add a 9th pillar or rename one.
5. **Stay bounded**: at most 2 new or refined bullets per cycle, at most 5
   per run. Skip anything already covered, anything repo-specific trivia,
   and anything you are not confident will recur.
6. **Append-only discipline**: add or refine bullets only. Never delete or
   rewrite another loop's bullets, and never reformat the file.
7. **Tool-agnostic bullets**: state trigger, hazard, and fix shape. Never
   name an agent, model, runtime, or assistant tool in a bullet.
8. **No signatures**: no author, date, or source tags on bullets.

---

## 4. Commit, rebase the stack & manage CI

1. **Commit.** Conventional Commits, staged by name, and never add AI
   attribution, co-author, or session trailers:
   ```bash
   git add <files you changed>
   git commit -m "fix(<scope>): <what the review feedback asked for>"
   ```
   Update the branch devlog in the same commit when the repo keeps one.
2. **Push.**
   - Stacked PR workflow:
     ```bash
     gh stack rebase && gh stack submit --auto
     ```
   - Plain branch: always push with an explicit destination refspec, never
     a bare `git push -u origin <branch>`, which can resolve to `main`
     through a stale upstream:
     ```bash
     git push -u origin HEAD:refs/heads/<type>/<branch-name>
     ```
3. **Cancel superseded CI runs.** Every push queues a build; cancel runs
   on this PR's branch whose head SHA is no longer the tip:
   ```bash
   snap=$(gh pr view <pr_number> --json headRefName,headRefOid --jq '[.headRefName, .headRefOid] | @tsv') || { echo "ERROR: gh pr view failed; refusing to cancel" >&2; exit 1; }
   read -r branch tip <<<"$snap"
   if [ -z "$branch" ] || [ -z "$tip" ] || [ "$branch" = "null" ] || [ "$tip" = "null" ]; then echo "ERROR: no branch or tip SHA; refusing to cancel" >&2; exit 1; fi
   runs=$(gh api --paginate --method GET "/repos/{owner}/{repo}/actions/runs" -f branch="$branch" --jq '.workflow_runs[] | select(.status != "completed") | "\(.id) \(.head_sha)"') || { echo "ERROR: run listing failed; leaving runs uncancelled" >&2; exit 1; }
   tip_now=$(gh pr view <pr_number> --json headRefOid --jq .headRefOid) || { echo "ERROR: tip re-read failed; refusing to cancel" >&2; exit 1; }
   if [ -z "$tip_now" ] || [ "$tip_now" = "null" ]; then echo "ERROR: empty tip SHA on re-read; refusing to cancel" >&2; exit 1; fi
   if [ -n "$runs" ]; then
     printf '%s\n' "$runs" | while read -r id sha; do
       [ -n "$id" ] || continue
       [ "$sha" = "$tip_now" ] || gh run cancel "$id" || echo "WARNING: could not cancel run $id" >&2
     done
   fi
   ```
   The guards matter: a failed lookup, an empty branch, or an empty tip
   must never widen into cancelling other branches' runs. The branch
   travels as an encoded API parameter (never interpolated into the URL),
   unfinished runs of every status are listed (gated runs leak past a
   queued-only filter), and the tip is re-read after listing so a
   concurrent push's fresh runs are never cancelled.
4. **Resolve addressed review threads** via GraphQL, once the fix is
   pushed:
   ```bash
   gh api graphql -f query='
   mutation($threadId: ID!) {
     resolveReviewThread(input: {threadId: $threadId}) {
       thread { isResolved }
     }
   }' -F threadId="$THREAD_ID" || { echo "ERROR: thread resolve failed for $THREAD_ID; retry or resolve manually"; exit 1; }
   ```
5. **Verify CI.** Poll bounded until checks settle (at most 30 rounds,
   60 seconds apart; a timeout counts as inconclusive and is reported as
   such), then read the status column:
   ```bash
   for i in $(seq 1 30); do
     out=$(gh pr checks <pr_number> --json name,bucket); rc=$?
     if [ $rc -ne 0 ] && ! echo "$out" | jq -e . >/dev/null 2>&1; then echo "WARNING: checks fetch failed (attempt $i of 30); retrying"; sleep 60; continue; fi
     printf '%s\n' "$out"
     settle=$(echo "$out" | jq -r '[.[].bucket] | if any(. == "pending") then "wait" else "done" end') || { echo "WARNING: checks parse failed (attempt $i of 30); retrying"; sleep 60; continue; }
     [ "$settle" = "done" ] && break
     if [ "$i" -lt 30 ]; then sleep 60; fi
   done
   ```
   `gh pr checks --watch` **exits 0 even when checks fail**, so never
   trust its exit code. Read the status column, or:
   ```bash
   gh run list --branch <branch> --json conclusion,name,status
   ```
   If a check is red, first check whether `main` is red too before
   blaming the branch. Run at most 3 fix cycles per invocation (each
   pass through fetch, fix, and push is one cycle); if the cap is reached
   with checks still red, stop and report the failing checks, whether
   `main` is red too, and the suspected cause.

---

## 5. Output summary

Give the user a structured summary:

1. **Reviewed scope**: PR number plus the `triage_sha` printed by the
   section 1A resolve step, so a mid-run push shows as drift.
2. **Addressed review items**: each comment handled, with file paths, line
   numbers, and what changed.
3. **False positives / dismissed feedback**: with the technical
   justification and disproving command for each.
4. **Shared pillars updated**: which pillar bullets in the shared
   refinements file were added or refined per cycle (with pillar numbers),
   and which redundant specific checks were folded in.
5. **Stack & CI status**: current commit SHA, stack sync state, and the
   real check results.
