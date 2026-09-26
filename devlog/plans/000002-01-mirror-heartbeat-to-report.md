# 000002-01-mirror-heartbeat-to-report.md

## Thinking

Commit 6cea4d7 added the progress heartbeat, stall detection, and bounded
search rules to `agent-review-loop` only. `agent-review-report` fans out
the same 8 parallel reviewers plus synthesis, so it has the same stall
exposure: one silent reviewer holds the single round open with only the
runtime default timeout as backstop. The report skill also carries an
explicit "keep reviewer prompt bullets in sync" mirror note, which the
loop-only change broke: the loop brief now has two bullets (exact paths
and bounded search, progress heartbeat) that the report brief lacks.

`agent-review-pr-comments` runs `gh` and `git` directly with no subagents,
so heartbeat does not apply there; no change needed.

The mirror needs report-specific adaptations, not a verbatim copy. The
report runs exactly one round, so progress file naming drops the round
number (`/tmp/agent-review-report-<lens>.progress`). Report wording says
"report header" where the loop says "round summary", and "uncovered" where
the loop says "uncovered next round". Cleanup lives in section 8, and the
protocol intro says "(or timed out after one re-prompt)", which must point
at the stall rule instead. Synthesis keeps its existing cancel-before-
synthesis line; like the loop's synthesis pass, it gets no separate
heartbeat file.

## Plan

1. Section 4 protocol intro: replace "(or timed out after one re-prompt)"
   with stall-rule wording, and "has timed out" with "has stalled out".
2. After the collect paragraph (re-prompt once, then cancel), insert the
   stall paragraph adapted to report wording: 15 minute silence window
   counted from spawn or last progress line, one nudge message, 5 minute
   grace period, one replacement reviewer, then proceed noting the missing
   lens in the report header and treating its pillars as uncovered.
3. Add the exact-paths/bounded-search and progress-heartbeat bullets to
   the reviewer prompt list, mirroring the loop brief with the report
   progress file naming.
4. Section 8: extend scratch cleanup to every per-reviewer progress file.
5. Verify: em dash grep over the worktree bundle, `./tests/verify-install.sh`
   from the worktree, and a side by side read of both skills to confirm
   the mirror notes hold again.
