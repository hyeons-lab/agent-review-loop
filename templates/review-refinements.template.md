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
whenever adding or merging bullets, clean up the total bullets in that pillar
so they stay organized and evolve over time: do not just keep adding new
bullets without cleaning up the total bullets after adding them (it is a
living document); standing rule: every bullet must help a review in a
different repo on a different stack (file repo-specific lessons in the
repo-local file); consolidate overlapping concepts and eliminate redundancy;
never add a 9th pillar or rename one; re-read this file immediately before
editing; create an automatic timestamped backup in backups/ before editing;
if backups accumulate (more than 5), ask the user in chat whether to prune
older ones; use surgical chunk replacement rather than whole-file overwrites.

---

### Pillar 1: Functional Correctness, Logic & Edge Cases
<!-- Loops append bullets here. -->
- **Boundary condition and empty collection guards**: When processing collection slicing, array indexing, sequence iterations, or state transitions across execution branches, guard against off-by-one boundary offsets, empty collections, stale branch bindings, and null or undefined elements; fix by validating length and index ranges at function entry, invalidating stale state across conditional barriers, and using safe lookups with explicit defaults rather than direct unchecked indexing.

### Pillar 2: Security, Authentication & Input Sanitization
<!-- Loops append bullets here. -->
- **Boundary input sanitization and command containment**: When accepting user-supplied parameters into system shells, database queries, file paths, or template engines, guard against command injection, query injection, path traversal escapes, and overly permissive artifact permissions; fix by using parameterized APIs, canonicalizing paths against a trusted base directory, enforcing restrictive file creation modes, and rejecting unvalidated metacharacters at the boundary.

### Pillar 3: Concurrency, Asynchrony & Lifecycle Management
<!-- Loops append bullets here. -->
- **Guaranteed cleanup and lifecycle independence**: When managing asynchronous tasks, background workers, timers, temporary storage, or exclusive resource locks, ensure cancellation signals and error unwinding release held locks, terminate child routines, and purge temporary scratch artifacts; fix by acquiring resources through RAII guards or exit traps and decoupling cleanup execution from optional conditional approval paths.

### Pillar 4: Error Handling, Resilience & Diagnostics
<!-- Loops append bullets here. -->
- **Explicit error propagation, destination guards, and atomic state updates**: When handling recoverable operational errors, capturing failure diagnostics, or persisting state changes, return typed error representations instead of crashing or masking local filesystem failures as remote errors, and guard against directory collisions or non-atomic partial writes; fix by validating staging paths and destination types before writing, propagating descriptive error types with actionable recovery guidance, staging modifications through uniquely named temporary files, and overwriting destinations via atomic rename.

### Pillar 5: Interface Contracts, API Design & Compatibility
<!-- Loops append bullets here. -->
- **Contract parameter fidelity, notation consistency, and schema synchronization**: When passing options, configurations, or CLI arguments through multi-tiered architectures or across service/client boundaries, ensure parameters are forwarded without silent dropping, notation divergence, or default skew; fix by defining contracts from a single source of truth, standardizing placeholder conventions, and validating contract schema conformance at boundary entries.

### Pillar 6: Performance, Resource Efficiency & Scalability
<!-- Loops append bullets here. -->
- **Hot-path allocation discipline and batch processing**: When processing repetitive loops, high-frequency request pipelines, or bulk data streams, avoid redundant memory allocations, unnecessary intermediate copies, and repeated fine-grained lock or network round-trips; fix by pre-allocating reusable scratch buffers, streaming large datasets, and batching fine-grained operations.

### Pillar 7: Code Simplification, Clean Architecture & Maintainability
<!-- Loops append bullets here. -->
- **Linear control flow, single-pass resolution, and premature abstraction removal**: When structuring decision logic, normalizing options, or refactoring existing modules, avoid deeply nested conditionals, fragmented multi-pass option resolution, dead code branches, and redundant ancestor operations; fix by replacing nested branches with early return guard clauses, consolidating normalization into single-pass pipelines, deleting obsolete routines, and relying on canonical helpers.

### Pillar 8: Testing, Observability & Verification Invariants
<!-- Loops append bullets here. -->
- **Non-vacuous regression testing, attribute verification, and failure observability**: When writing automated tests, linter checks, or updating metadata, ensure assertions fail on real faults, verify behavioral invariants (such as non-owner file permissions and exact planned mutation counts) rather than unasserted tallies, and preserve diagnostic context on error; fix by asserting behavioral invariants on failure paths, checking exit codes directly without fallbacks masking failures, and retaining diagnostic execution logs when test assertions fail.
