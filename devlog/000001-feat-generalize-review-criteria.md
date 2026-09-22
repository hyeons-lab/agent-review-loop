# 000001-feat-generalize-review-criteria.md

**Agent:** Antigravity (Gemini 3.8 Flash) @ repository branch feat/generalize-review-criteria  
**Intent:** Generalize review criteria and pillars for any repository, make legacy refinements opt-in via REVIEW_REFINEMENTS_LEGACY=1, enforce repo-local placement for stack-specific lessons, and seed canonical refinements with general cross-stack bullets.

## Decisions

- 2026-09-21T17:08-07:00 Preserve 8 pillar headings byte-for-byte: The titles `### Pillar 1:` through `### Pillar 8:` form a frozen contract across review loops and must remain untouched.
- 2026-09-21T17:08-07:00 Make legacy refinements opt-in via REVIEW_REFINEMENTS_LEGACY=1: The 322-line legacy file contains project-specific Rust/GPU/inference bullets that add noise to non-inference projects; default to skipping it unless explicitly requested.
- 2026-09-21T17:08-07:00 Seed 8 domain-neutral bullets in canonical refinements: Populate one high-signal, stack-agnostic principle per pillar in `~/.agents/review-refinements.md` and the starter template, keeping the existing Pillar 6 license attribution bullet intact.
- 2026-09-21T17:37-07:00 Adopt canonical software engineering review pillars: Completely replace legacy systems/inference pillar categories with 8 universal software engineering pillars (Correctness, Security, Concurrency, Error Handling, API Design, Performance, Simplicity, Testing/Observability).
- 2026-09-21T17:46-07:00 Align agent-review-report with canonical SWE pillars: Harmonized the incorporated report skill with the 8 canonical software engineering review pillars and legacy opt-in semantics.
- 2026-09-21T18:04-07:00 Codify explicit refinements filing protocol: Added step-by-step instructions in SKILL.md for fresh read, canonical pillar classification, in-place subsumption vs section insertion, bullet formatting, immediate verification, and next-round prompt injection.
- 2026-09-21T18:08-07:00 Atomically replace symlinks without pre-deletion: In POSIX, `mv -f` over a symlink replaces the link atomically via `rename(2)` without following it; removing pre-deletion eliminates any non-atomic window.
- 2026-09-21T18:08-07:00 Isolate test harness runs and logs via mktemp: Replaced static `/tmp` paths in test runner with a trap-cleaned temporary directory to prevent race conditions and collision hazards.
- 2026-09-21T19:31-07:00 Preserve file permissions in copy_atomic via cp -p: POSIX mktemp generates mode 0600 files; without -p, copying retains restrictive permissions that break non-root, container, or group access to installed skills.
- 2026-09-21T19:31-07:00 Reconcile test runner error checks and non-vacuous assertions: Replaced systematic || true swallows with structured run_install execution under check helper, guaranteeing all installer invocations are asserted for exit 0 while avoiding premature test suite aborts.
- 2026-09-21T19:31-07:00 Align diff redirection and cleanup across review skills: Explicitly redirected working diffs to scratch files in agent-review-report to honor the diagnostic prompt contract and added guaranteed cleanup traps in address-pr-comments.
- 2026-09-21T19:39-07:00 Guard atomic file copy against directory collisions: In copy_atomic, reject destination paths that are existing directories before creating temporary staging files to avoid silently moving temporary files into directories.
- 2026-09-21T19:39-07:00 Retain diagnostic logs on test assertion failures: Updated verify-install.sh harness trap to retain the log directory and print failed command output when assertions fail, ensuring CI and local debugging have full error context.
- 2026-09-21T19:39-07:00 Unconditionally decouple diff scratch cleanup from PR posting approval: Moved scratch diff file cleanup in agent-review-report to a dedicated concluding section so that local reviews and unapproved PR reviews do not leak temporary files.
- 2026-09-21T19:58-07:00 Explicitly scope read-only invariant in agent-review-report: Core Invariant 3 was scoped specifically to the repository and code under review, making the refinements file an explicit exception per Section 7 so reviewers are not blocked from recording durable learnings.
- 2026-09-21T22:22-07:00 Adopt living document synthesis protocol for review refinements: Replaced artificial per-round numerical caps with a living document model where all actionable review suggestions are incorporated by actively rewriting and generalizing existing bullets across pillars.
- 2026-09-21T22:28-07:00 Mandate add/merge and total bullet cleanup pass: Explicitly required review agents to either merge suggestions into existing bullets or add new ones, followed by a total cleanup pass over that pillar's bullets so the document stays organized and evolves over time rather than accumulating unbounded additions.
- 2026-09-21T22:38-07:00 Prefix all skills under agent-review- namespace: Renamed address-pr-comments to agent-review-pr-comments, unifying the suite into /agent-review-loop, /agent-review-report, and /agent-review-pr-comments.
- 2026-09-21T22:40-07:00 Support seamless legacy skill migration under upgrade: Added legacy_skill_name mapping and migration logic in install.sh so ./install.sh --upgrade detects previous address-pr-comments installs, migrates them to agent-review-pr-comments, updates them, and removes obsolete directories.
- 2026-09-21T22:50-07:00 Automatic timestamped backups and accumulation pruning prompts: Required review agents to create timestamped snapshots in backups/ before editing review-refinements.md, use surgical chunk replacement scoped to single pillars, verify the 8-pillar structural invariant, and ask the user before pruning older backups when they accumulate beyond 5 snapshots.

## What Changed

- 2026-09-21T17:08-07:00 `devlog/plans/000001-01-generalize-review-criteria.md`: Initial implementation plan for generalizing review criteria.
- 2026-09-21T17:11-07:00 `skills/agent-review-loop/thematic-review-pillars.md`: Rewrote base pillar bullets domain-neutral using trigger/hazard/fix-shape structure, demoting systems cases to parenthetical examples; preserved 8 pillar headings byte-for-byte; updated resolution order and added standing generality rule.
- 2026-09-21T17:11-07:00 `skills/agent-review-loop/SKILL.md`: Updated resolution order with REVIEW_REFINEMENTS_LEGACY=1 opt-in and prioritized repo-local over canonical; strengthened write target rules with the standing cross-stack generality requirement.
- 2026-09-21T17:11-07:00 `skills/address-pr-comments/SKILL.md`: Aligned resolution order and write target rules with REVIEW_REFINEMENTS_LEGACY=1 and the standing generality requirement.
- 2026-09-21T17:11-07:00 `README.md`: Documented REVIEW_REFINEMENTS_LEGACY=1, repo-local vs canonical refinements placement, and the standing rule for cross-stack bullet generality.
- 2026-09-21T17:11-07:00 `install.sh`: Updated legacy refinements note on seed to inform users that REVIEW_REFINEMENTS_LEGACY=1 is needed to include legacy files in reviews.
- 2026-09-21T17:11-07:00 `tests/verify-install.sh`: Added test assertion verifying REVIEW_REFINEMENTS_LEGACY=1 is mentioned in the legacy install note.
- 2026-09-21T17:11-07:00 `templates/review-refinements.template.md`: Added 8 domain-neutral seed bullets (one per pillar) and updated writer rules with the standing generality rule.
- 2026-09-21T17:37-07:00 `skills/agent-review-loop/thematic-review-pillars.md`: Replaced systems/inference pillar categories with 8 canonical software engineering review pillars.
- 2026-09-21T17:37-07:00 `skills/agent-review-loop/SKILL.md`: Updated reviewer pillar list to match the 8 canonical software engineering pillars.
- 2026-09-21T17:37-07:00 `README.md`: Updated pillar descriptions to reference the canonical software engineering pillars.
- 2026-09-21T17:37-07:00 `templates/review-refinements.template.md`: Updated template headers and starter bullets to canonical software engineering pillars.
- 2026-09-21T17:37-07:00 `devlog/plans/000001-01-generalize-review-criteria.md`: Appended note on transition to canonical SWE pillars.
- 2026-09-21T17:46-07:00 `devlog/plans/000001-02-incorporate-agent-review-report.md`: Plan for incorporating agent-review-report skill into PR 2.
- 2026-09-21T17:46-07:00 `skills/agent-review-report/agents/openai.yaml`: Added Codex metadata for agent-review-report skill.
- 2026-09-21T17:46-07:00 `skills/agent-review-report/SKILL.md`: Added agent-review-report skill definition adapted to canonical SWE review pillars and REVIEW_REFINEMENTS_LEGACY=1 opt-in.
- 2026-09-21T17:46-07:00 `install.sh`: Added agent-review-report to SKILLS, skill_files, and completion message.
- 2026-09-21T17:46-07:00 `tests/verify-install.sh`: Added agent-review-report to verification suite across all test sections.
- 2026-09-21T17:46-07:00 `README.md`: Updated description, contents, install tables, uninstall paths, and manual install steps for 3 skills.
- 2026-09-21T17:46-07:00 `skills/address-pr-comments/SKILL.md`: Updated cross-skill refinements reference.
- 2026-09-21T17:46-07:00 `skills/agent-review-loop/SKILL.md`: Added mirroring sync note with agent-review-report.
- 2026-09-21T17:46-07:00 `skills/agent-review-loop/thematic-review-pillars.md`: Updated skill name list in document header.
- 2026-09-21T18:04-07:00 `skills/agent-review-loop/SKILL.md`: Added concrete step-by-step refinements update protocol, clarified reviewer assignment across effort levels using canonical pillar names, and constrained next-round prompt injection to current-loop bullets.
- 2026-09-21T18:04-07:00 `skills/agent-review-report/SKILL.md`: Aligned Section 7 refinements update protocol with agent-review-loop.
- 2026-09-21T18:04-07:00 `skills/address-pr-comments/SKILL.md`: Added scratch directory isolation for comment dumps and strengthened checks settle parser.
- 2026-09-21T18:08-07:00 `skills/address-pr-comments/SKILL.md`: Aligned Section 1.B pillar list with the 8 canonical software engineering review pillars.
- 2026-09-21T18:08-07:00 `skills/agent-review-report/SKILL.md`: Added credential redaction invariant, hardened PR argument validation and error diagnostics, added timed-out reviewer cancellation before synthesis, removed `.md` suffix from mktemp template, added comment cleanup, and enforced cross-stack requirement.
- 2026-09-21T18:08-07:00 `skills/agent-review-loop/SKILL.md`: Aligned Section 4 diff extraction with clean-tree branch diff detection, recursive wildcards, and scratch file handling.
- 2026-09-21T18:08-07:00 `skills/agent-review-loop/thematic-review-pillars.md`: Added note in Section 1 on legacy refinements following pre-generalization pillar numbering.
- 2026-09-21T18:08-07:00 `install.sh`: Used `mktemp` in `copy_atomic`, removed non-atomic deletion before symlink overwrite, moved legacy notice before early-return guard in `seed_refinements`, expanded `verify_skill` to check all bundled files, and consolidated base directory definitions.
- 2026-09-21T18:08-07:00 `tests/verify-install.sh`: Isolated test environment and logs to `mktemp -d` with trap cleanup, fixed shellcheck assertion chaining, added `|| true` on set -e runs to preserve failure reporting, asserted exact unchanged counts, used byte-identity checks, and asserted report skill retention.
- 2026-09-21T18:08-07:00 `templates/review-refinements.template.md`: Synchronized Pillar 4 and Pillar 8 starter bullets with refined atomic replacement and non-vacuous testing guidance.
- 2026-09-21T18:08-07:00 `~/.agents/review-refinements.md`: Refined Pillar 4 (atomic rename and unique temp files) and Pillar 8 (linter check isolation and exact mutation count assertions).
- 2026-09-21T19:31-07:00 `install.sh`: Preserved source file mode in copy_atomic via cp -p, verified current symlinks before evaluating dry-run mode in install_skill_link, guarded dry-run mkdir output against existing directories, fixed targets printf format string, and updated completion invocation hint to optional brackets [<pr>].
- 2026-09-21T19:31-07:00 `tests/verify-install.sh`: Replaced signal trap with EXIT, INT (exit 130), and TERM (exit 143) handlers; added run_install helper and wrapped all installer runs in check assertions to eliminate vacuous test passes; added populated home dry-run test; hardened em dash absence grep test against operational errors (exit code >= 2) and excluded worktrees.
- 2026-09-21T19:31-07:00 `skills/agent-review-report/SKILL.md`: Assigned diff_file and redirected filtered diff to scratch file in local diff snippet, added scratch diff file cleanup instruction upon report completion, skipped synthesis when all reviewers report NO FINDINGS, and aligned 8 Canonical Thematic Pillars terminology.
- 2026-09-21T19:31-07:00 `skills/address-pr-comments/SKILL.md`: Added trap cleanup for scratch_dir on fetch failures, and synchronized Section 3 with the 7-step refinements update protocol.
- 2026-09-21T19:31-07:00 `skills/agent-review-loop/SKILL.md`: Added subagent cancellation/termination on timeout before proceeding, and harmonized scratch diff path phrasing in reviewer prompt.
- 2026-09-21T19:31-07:00 `~/.agents/review-refinements.md`: Synchronized Pillar 4 (atomic rename and unique temp files) and Pillar 8 (exit code assertions without masking and exact mutation counts) with template starter bullets.
- 2026-09-21T19:39-07:00 `skills/agent-review-report/SKILL.md`: Nested local diff filtering snippet under No argument bullet in Section 1, removed redundant scratch diff cleanup from Section 6 PR approval block, and added Section 8 Finishing Up for unconditional diff cleanup.
- 2026-09-21T19:39-07:00 `skills/address-pr-comments/SKILL.md`: Added error check on mktemp -d for scratch_dir and hardened parameter expansion in cleanup trap.
- 2026-09-21T19:39-07:00 `install.sh`: Added directory destination guard in copy_atomic, simplified destination directory existence check in install_skill_copy, consolidated target normalization and deduplication into a single pass, and updated /agent-review-report invocation placeholder to [<pr>].
- 2026-09-21T19:39-07:00 `tests/verify-install.sh`: Hardened test harness with cleanup function retaining diagnostic logs on failure, captured failure output in check helper, added non-owner file readability assertion, and added assertion for 35 planned file installs on empty-home dry run.
- 2026-09-21T19:58-07:00 `skills/agent-review-report/SKILL.md`: Scoped Core Invariant 3 to code under review and clarified the refinements write exception to resolve Copilot review finding.
- 2026-09-21T22:22-07:00 `devlog/plans/000001-03-living-document-refinements.md`: Implementation plan for living document review refinements protocol and active bullet generalization.
- 2026-09-21T22:22-07:00 `templates/review-refinements.template.md`: Removed per-round bullet quotas, codified living document synthesis rules, and generalized starter bullets across all 8 canonical SWE pillars.
- 2026-09-21T22:22-07:00 `skills/agent-review-loop/SKILL.md`: Updated Section 6 with living document synthesis protocol and comprehensive suggestion incorporation.
- 2026-09-21T22:22-07:00 `skills/agent-review-report/SKILL.md`: Aligned Section 7 update protocol with living document synthesis and comprehensive suggestion incorporation.
- 2026-09-21T22:22-07:00 `skills/address-pr-comments/SKILL.md`: Synchronized Section 3 update protocol with living document synthesis and comprehensive suggestion incorporation.
- 2026-09-21T22:22-07:00 `skills/agent-review-loop/thematic-review-pillars.md`: Updated Section 3 self-improvement protocol with living document synthesis and bullet generalization.
- 2026-09-21T22:22-07:00 `README.md`: Documented living document synthesis model in Shared Pillars File section.
- 2026-09-21T22:22-07:00 `~/.agents/review-refinements.md`: Rewrote active bullets across 8 pillars into generalized living principles incorporating recent review learnings.
- 2026-09-21T22:28-07:00 `templates/review-refinements.template.md`: Codified add or merge rules and mandated total bullet cleanup pass to ensure bullets remain organized and evolve over time.
- 2026-09-21T22:28-07:00 `~/.agents/review-refinements.md`: Synchronized header rules with add or merge directives and total bullet cleanup pass requirement.
- 2026-09-21T22:28-07:00 `skills/agent-review-loop/SKILL.md`: Updated Section 6 Steps 3, 5, and 7 to enforce add/merge decisions and post-addition total bullet cleanup across pillars.
- 2026-09-21T22:28-07:00 `skills/agent-review-report/SKILL.md`: Aligned Section 7 Steps 3, 5, and 7 with add/merge and total bullet cleanup directives.
- 2026-09-21T22:28-07:00 `skills/agent-review-pr-comments/SKILL.md`: Synchronized Section 3 Steps 3, 5, and 7 with add/merge and total bullet cleanup directives.
- 2026-09-21T22:28-07:00 `skills/agent-review-loop/thematic-review-pillars.md`: Updated Section 3 self-improvement steps with add/merge and total bullet cleanup rules.
- 2026-09-21T22:28-07:00 `README.md`: Updated Shared Pillars File section with add/merge and total bullet cleanup living document evolution.
- 2026-09-21T22:28-07:00 `devlog/plans/000001-03-living-document-refinements.md`: Appended add/merge and total bullet cleanup evolution specification.
- 2026-09-21T22:38-07:00 `devlog/plans/000001-04-prefix-skills-rename-pr-comments.md`: Implementation plan for unifying skill prefixes and renaming address-pr-comments to agent-review-pr-comments.
- 2026-09-21T22:38-07:00 `skills/agent-review-pr-comments/`: Renamed skill directory from skills/address-pr-comments; updated frontmatter name and openai.yaml metadata.
- 2026-09-21T22:38-07:00 `install.sh`: Updated SKILLS, skill_files mapping, help text, and invocation hints to agent-review-pr-comments.
- 2026-09-21T22:38-07:00 `tests/verify-install.sh`: Updated SKILLS list and upgrade tests to verify agent-review-pr-comments.
- 2026-09-21T22:38-07:00 `README.md`: Updated skill lists, tables, invocation examples, uninstall snippets, and manual copy paths to agent-review-pr-comments.
- 2026-09-21T22:38-07:00 `skills/agent-review-report/SKILL.md`: Updated suggested next step reference to agent-review-pr-comments.
- 2026-09-21T22:38-07:00 `skills/agent-review-loop/thematic-review-pillars.md`: Updated shared base pillars skill list to include agent-review-pr-comments.
- 2026-09-21T22:40-07:00 `install.sh`: Added legacy_skill_name helper and migration handling in upgrade_skill, install_skill_copy, and install_skill_link to migrate address-pr-comments to agent-review-pr-comments and purge obsolete directories.
- 2026-09-21T22:40-07:00 `tests/verify-install.sh`: Added test assertions in Section 9 verifying --upgrade migrates legacy address-pr-comments to agent-review-pr-comments, updates content, and removes the old directory.
- 2026-09-21T22:45-07:00 `devlog/plans/000001-05-automatic-refinement-backups.md`: Implementation plan for automatic timestamped refinement backups and prune prompting.
- 2026-09-21T22:45-07:00 `.gitignore`: Added `.agents/backups/` ignore pattern.
- 2026-09-21T22:45-07:00 `skills/agent-review-loop/SKILL.md`: Added timestamped backup snapshot step, surgical chunk replacement requirement, structural invariant check, and greater than 5 backup accumulation prune prompt.
- 2026-09-21T22:45-07:00 `skills/agent-review-report/SKILL.md`: Aligned Section 7 with timestamped backup step, surgical chunk replacement, structural verification, and backup accumulation prune prompt.
- 2026-09-21T22:45-07:00 `skills/agent-review-pr-comments/SKILL.md`: Aligned Section 3 with timestamped backup step, surgical chunk replacement, structural verification, and backup accumulation prune prompt.
- 2026-09-21T22:45-07:00 `templates/review-refinements.template.md`: Documented backup preservation rules, surgical editing, and pruning threshold.
- 2026-09-21T22:45-07:00 `~/.agents/review-refinements.md`: Added header instructions for timestamped backups, chunk-level editing, structural invariants, and pruning threshold prompt.
- 2026-09-21T22:45-07:00 `README.md`: Documented automatic timestamped backups and maintenance under Shared Pillars File.

## Issues

## Commits

- c897bc9: feat: generalize review criteria across repositories and stacks
- cddbd79: refactor: adopt canonical software engineering review pillars
- 5cc6428: feat: incorporate agent-review-report skill
- a1dd2fe: feat(refinements): codify canonical SWE pillar update protocol for review refinements
- 063bb3f: fix(review): harden installer, verification harness, and skill lifecycles
- d1d139a: fix(agent-review-report): scope read-only invariant to code under review
- HEAD: feat: adopt living document refinements, unified prefix, and automated backups

