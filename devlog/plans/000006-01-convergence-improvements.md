# Plan: make agent-review-loop converge faster

Source: an 8 round review loop over a 20 PR stack (about 80M subagent tokens). Full rounds produced 78, 61, 52, 89 and 73 findings instead of falling toward zero. The analysis below turns what that run showed into changes to `skills/agent-review-loop/SKILL.md` (and the pieces of the sibling skills and tests that mirror it).

## Thinking

What the run showed.
- **Fix churn feeds the next round.** Each fix pass changed 60 to 90 places, including every nitpick and quality item. In late rounds a large share of the new correctness findings were defects in the previous fix commit (a bisect fix that starved healthy rows, a supersede fix that orphaned an in-flight row, a non-atomic migration). More churn means more new surface.
- **Sampling, not coverage.** Four pillar lenses read a large diff with finite attention, so each round surfaces a different slice of a big defect pool. Counts bounce instead of falling, and nothing in the skill records which code has actually been read.
- **No estimate of what remains.** "No findings this round" is the only stop signal, and the count includes nitpicks that vary with reviewer mood.
- **Claims by reading.** Many correctness findings were verified by "read". Reproduced findings are almost always real; unreproduced ones cost fix effort and add churn.
- **Reviewers rediscover classes.** The same defect classes (async persist versus commit, uncancelled sign-out, retry versus permanent classification) recurred in different scopes, and a sweep ran only inside fixers.
- **Fix-check is shallow.** It runs targeted tests but does not try to break the fix.
- **Effort is uniform.** The biggest and riskiest scopes get the same lens count as trivial ones.

Design principles for the changes.
- Prefer deterministic evidence (a probe, a tool run, a recorded range) over more reviewer prose.
- Keep every existing invariant: the 8 canonical pillars by number and name, zero AI attribution, no em dashes, no push without approval, credential redaction, verification gate, the full confirmation round after a narrowed clean round.
- Every new behavior is optional or has a stated default, and degrades to today's behavior when its inputs are absent (no coverage ledger, a runtime without subagents, a repo with no deep tools).
- Do not grow the skill without bound: new material goes into existing sections, with one new section for the run ledger.

## Plan

Each step is one commit and ends with `tests/verify-install.sh` green.

1. **Convergence phase and severity gate.** Add a "convergence phase": rounds fix only bug, correctness and convention findings; quality and nitpick findings go to a run backlog and are applied once in a final polish pass followed by one full confirming round. `all-severities` mode keeps today's behavior. Update the Section 2 invariants, Step 2 classification (what "Actionable" means per phase) and Step 3.
2. **Finding provenance and the new-class stop rule.** Findings gain `origin` (original, fix-induced, recurrence), `class` (slug) and `newClass`. Step 6 reports the three counts. Stop rule: no new bug or correctness class and no fix-induced finding for two consecutive full rounds, with nitpicks and quality never blocking.
3. **Executable evidence and the tooling ladder.** Bug and correctness findings need a probe or are marked `unreproduced` by synthesis and held out of the fix list until reproduced or explicitly accepted. Add a per-round "tooling ladder" step that detects and runs the repo's deeper tools once and feeds the output to reviewers (strict lints, sanitizers, fuzz or property tests, coverage for untested branches, mutation testing), recording each skipped tool and why. Never installs tools silently.
4. **Fix-check as regression hunter, fixer class sweep.** Step 3 requires a class sweep (grep the scope for siblings of every fixed class), a failure-path self-review and a hostile read of the diff before commit. Step 4 adds adversarial probes per fix (cancel mid-way, repeat, maximum and empty input, restart), a written "what could go wrong" list, and the full gate instead of targeted tests only.
5. **Cross-scope class sweep.** Synthesis emits each class as a grep or checklist; a new Step 2b runs it over every scope in the run (all PRs of a stack, or the whole repo) in the same round. Findings from it are tagged `sweep`.
6. **Coverage ledger and sharding.** A new section defines a run ledger (`coverage.json`: file, range, last round read, reviewer, changed since). Large diffs are sharded by module with overlap; reviewers report `rangesRead`; the next round's lens scoping adds coverage debt (unread or changed-since ranges) to the dirty-set rule.
7. **Redundancy and the capture-recapture estimate.** An optional `redundancy 2` runs two independent reviewers per lens (default on for full confirmation rounds). Synthesis computes the overlap and reports the Chapman estimate of residual defects `N = (n1+1)(n2+1)/(m+1) - 1`, minus the union. The stop rule can use an estimate below one.
8. **Effort routing.** Per-scope effort override (`max` for scopes above a size or churn threshold, or named hot scopes), documented as coverage routing and not as de-escalation, with the Section 2 "fixed effort" invariant amended accordingly.
9. **Mirrors, tests and docs.** Update the sibling skills where they mirror round files (`agent-review-report`), `README.md`, and `tests/verify-install.sh` pins for every new section and flag. Dogfood: run the changed skill on its own diff.

## Risks

- **Skill size.** SKILL.md is already about 1000 lines. Mitigation: tight edits to existing sections; the ledger gets one section; nothing is duplicated into the sibling skills.
- **Cost.** Redundancy doubles reviewer cost, so it defaults to full confirmation rounds only; sharding keeps per-reviewer context bounded.
- **Behavior drift in other runtimes.** Muse, Codex and Antigravity use the same SKILL.md; every new step states its fallback when a capability is missing.
- **Mirror pins.** The bootstrap mirror spans and tests pin exact text; edits near them must keep `verify-install.sh` green and regenerate goldens only deliberately.
