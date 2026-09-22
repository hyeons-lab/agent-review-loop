# Shared Review Refinements

User-local code review refinements shared by every review loop across Muse,
Claude Code, Codex, and Antigravity/Gemini. Loops read this file plus the
bundled base pillars (`thematic-review-pillars.md`) and file genuinely novel
learnings here when a round ends (when a fix cycle ends, for PR runs).

Bullet format (one principle per bullet, filed under its pillar):

- **Title**: principle stated as trigger, hazard, and fix shape. Generalize
  past the file where it was learned; never name an agent, model, runtime,
  or tool.

Rules for writers: add or merge suggestions into a clean, evolving list;
clean up the total bullets in each modified pillar so they stay organized
and evolve over time (do not accumulate unbounded additions without
consolidation in a living document); standing rule: every bullet must help a
review in a different repo on a different stack (file repo-specific lessons in the
repo-local file); consolidate overlapping concepts and eliminate redundancy;
never add a 9th pillar or rename one; re-read this file immediately before
editing; create an automatic timestamped backup in the backups/ directory
before editing; if backups accumulate (more than 5), ask the user in chat
whether to prune older ones; use surgical chunk replacement rather than
whole-file overwrites.

---

### Pillar 1: Functional Correctness, Logic & Edge Cases
<!-- Loops append bullets here. -->
- **Boundary Isolation and Specification Integrity**: When processing collection slicing, array indexing, sequence iterations, accumulating variable bindings across execution stages or nested scopes, or applying surgical replacements to multi-step workflows, guard against off-by-one boundary offsets, empty collections, stale or overridden branch bindings surviving into alternative paths, inner-scope assignments leaking into enclosing blocks, and fragmented chunk replacements that truncate sentences, drop constraints, or inject duplicate conflicting workflow sections; fix by validating length and index ranges at function entry, invalidating prior mappings across conditional barriers, tracking scope depth explicitly to isolate nested bindings, using safe lookups with explicit defaults, verifying chunk boundaries against surrounding context, and reading back documents to verify coherent linear flow.

### Pillar 2: Security, Authentication & Input Sanitization
<!-- Loops append bullets here. -->
- **Boundary input sanitization and command containment**: When accepting user-supplied parameters into system shells, database queries, file paths, or template engines, guard against command injection, query injection, path traversal escapes, and overly permissive artifact permissions; fix by using parameterized APIs, canonicalizing paths against a trusted base directory, enforcing restrictive file creation modes, and rejecting unvalidated metacharacters at the boundary.

### Pillar 3: Concurrency, Asynchrony & Lifecycle Management
<!-- Loops append bullets here. -->
- **Guaranteed Cleanup and Structural Rollback**: When managing asynchronous tasks, background workers, timers, temporary scratch storage, or modifying critical state under structural invariants, ensure cancellation signals, invariant violations, and error unwinding release held locks, terminate child routines, purge temporary scratch artifacts, and restore pre-edit state without relying on dynamic paths that advance over time; fix by acquiring resources through RAII guards or exit traps, retaining snapshot file paths in explicit variables rather than re-evaluating timestamps, verifying structural invariants after mutations, rolling back state from pre-modification snapshots or deleting newly created files upon invariant failures, and deterministically purging scratch storage at lifecycle completion.

### Pillar 4: Error Handling, Resilience & Diagnostics
<!-- Loops append bullets here. -->
- **Error Propagation and Non-Destructive Migration**: When handling recoverable operational errors, capturing failure diagnostics, persisting state changes, migrating existing resources, or falling back between alternative execution strategies, return typed error representations instead of crashing or masking local failures as remote errors, ensure existing resources are not unlinked or destroyed prior to verifying destination success, guard against directory collisions or uninspected mutation exits, and ensure fallback handler exit codes propagate rather than being swallowed; fix by validating staging paths and destination types before writing, staging replacements and verifying their integrity before removing superseded originals, logging diagnostic reasons when triggering strategy fallbacks, propagating fallback return statuses explicitly, staging modifications through uniquely named temporary files, and overwriting destinations via atomic rename.

### Pillar 5: Interface Contracts, API Design & Compatibility
<!-- Loops append bullets here. -->
- **Contract parameter fidelity, notation consistency, and schema synchronization**: When passing options, configurations, or CLI arguments through multi-tiered architectures or across service/client boundaries, ensure parameters are forwarded without silent dropping, notation divergence, or default skew; fix by defining contracts from a single source of truth, standardizing placeholder conventions, and validating contract schema conformance at boundary entries.

### Pillar 6: Performance, Resource Efficiency & Scalability
<!-- Loops append bullets here. -->
- **Hot-path allocation discipline and batch processing**: When processing repetitive loops, high-frequency request pipelines, or bulk data streams, avoid redundant memory allocations, unnecessary intermediate copies, and repeated fine-grained lock or network round-trips; fix by pre-allocating reusable scratch buffers, streaming large datasets, and batching fine-grained operations.

### Pillar 7: Code Simplification, Clean Architecture & Maintainability
<!-- Loops append bullets here. -->
- **Linear control flow, canonical helper consolidation, and boolean subsumption**: When structuring decision logic, normalizing options, cleaning up obsolete resources, or delegating between operational routines, avoid deeply nested conditionals, fragmented multi-pass resolution, duplicate banner logging across delegation layers, duplicated migration logic, and redundant boolean predicates that subsume one another; fix by replacing nested branches with early return guard clauses, consolidating repetitive migration or cleanup logic into single canonical helpers, suppressing duplicate section logging in internal delegation modes, and relying on comprehensive predicate abstractions without redundant sub-conditions.

### Pillar 8: Testing, Observability & Verification Invariants
<!-- Loops append bullets here. -->
- **Non-Vacuous Testing and Reachability Invariants**: When writing automated tests, linter checks, or updating metadata, ensure assertions fail on real faults, verify subordinate metadata and dereference symbolic links to assert file reachability rather than accepting dangling link metadata, avoid chaining test gates with fallback operators that mask test regressions behind file-not-found errors, verify dry-run modes plan operations while leaving disk state immutable, dynamically construct search patterns to avoid self-matching that forces test directory exclusion, and preserve diagnostic logs on early exit traps regardless of whether failures were caught by assert counters or shell aborts; fix by asserting behavioral invariants on failure paths, dereferencing links to verify readable contents, running test gates independently without masking fallbacks, asserting disk immutability in dry-run tests, checking exit codes directly, checking shell exit codes in exit traps to retain failure logs on unhandled aborts, generating search patterns dynamically (such as via byte formatting), and validating subordinate files alongside primary targets.
