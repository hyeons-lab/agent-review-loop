# Shared Review Refinements

User-local code review refinements shared by every review loop across Muse,
Claude Code, Codex, and Antigravity/Gemini. Loops read this file plus the
bundled base pillars (`thematic-review-pillars.md`) and file genuinely novel
learnings here when a round ends (when a fix cycle ends, for PR runs).

Bullet format (one principle per bullet, filed under its pillar):

- **Title**: principle stated as trigger, hazard, and fix shape. Generalize
  past the file where it was learned; never name an agent, model, runtime,
  or tool.

Rules for writers: at most 2 new or refined bullets per round (per fix
cycle) and 5 per run; standing rule: every bullet must help a review in a
different repo on a different stack (file repo-specific lessons in the
repo-local file); subsume into an overlapping bullet instead of adding
a sibling; never add a 9th pillar or rename one; append or refine only (no
deletes, no reformatting); re-read this file immediately before editing.

---

### Pillar 1: Functional Correctness, Logic & Edge Cases
<!-- Loops append bullets here. -->
- **Boundary condition and empty collection guards**: When processing collection slicing, array indexing, or sequence iterations, guard against off-by-one boundary offsets, empty collections, and null or undefined elements; fix by validating length and index ranges at function entry and using safe lookups with explicit defaults rather than direct unchecked indexing.

### Pillar 2: Security, Authentication & Input Sanitization
<!-- Loops append bullets here. -->
- **Boundary input sanitization and command containment**: When accepting user-supplied parameters into system shells, database queries, file paths, or template engines, guard against command injection, query injection, and path traversal escapes; fix by using parameterized APIs, canonicalizing paths against a trusted base directory, and rejecting unvalidated metacharacters at the boundary.

### Pillar 3: Concurrency, Asynchrony & Lifecycle Management
<!-- Loops append bullets here. -->
- **Guaranteed cleanup on cancellation and error unwinding**: When managing asynchronous tasks, background workers, timers, or exclusive resource locks, ensure cancellation signals and error exits release held locks, terminate child routines, and resolve pending completion states; fix by acquiring resources through RAII guards or try-finally blocks and resetting cancellation latches upon session reuse.

### Pillar 4: Error Handling, Resilience & Diagnostics
<!-- Loops append bullets here. -->
- **Explicit error propagation and atomic state updates**: When handling recoverable operational errors or persisting state changes, return typed error representations instead of crashing, force-unwrapping, or discarding error contexts, and avoid non-atomic partial writes; fix by propagating descriptive error types with actionable recovery guidance and staging file modifications through temporary writes followed by atomic renames.

### Pillar 5: Interface Contracts, API Design & Compatibility
<!-- Loops append bullets here. -->
- **Contract parameter fidelity and schema synchronization**: When passing options, configurations, or parameters through multi-tiered architectures or across service/client boundaries, ensure parameters are forwarded without silent dropping or default divergence; fix by defining contracts from a single source of truth and validating contract schema conformance at boundary entries.

### Pillar 6: Performance, Resource Efficiency & Scalability
<!-- Loops append bullets here. -->
- **Hot-path allocation discipline and batch processing**: When processing repetitive loops, high-frequency request pipelines, or bulk data streams, avoid redundant memory allocations, unnecessary intermediate copies, and repeated fine-grained lock or network round-trips; fix by pre-allocating reusable scratch buffers, streaming large datasets, and batching fine-grained operations.

### Pillar 7: Code Simplification, Clean Architecture & Maintainability
<!-- Loops append bullets here. -->
- **Linear control flow and premature abstraction removal**: When structuring decision logic or refactoring existing modules, avoid deeply nested conditionals, dead code branches, and unnecessary layers of indirection that obscure business logic; fix by replacing nested branches with early return guard clauses, deleting obsolete routines, and consolidating duplicate logic into canonical helpers.

### Pillar 8: Testing, Observability & Verification Invariants
<!-- Loops append bullets here. -->
- **Non-vacuous regression testing and license completeness**: When writing automated tests or updating license metadata, ensure test assertions fail on real faults, and verify copyright notices name the actual holder with matching terms; fix by asserting behavioral invariants on failure paths and aligning license notices with files on disk.
