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

### Pillar 1: Low-Level Safety, Alignment & Buffer Invariants
<!-- Loops append bullets here. -->
- **Bounded buffer reads and layout validation**: When reading binary payloads, deserializing data streams, or slicing memory buffers (such as packet decoders, file parsers, or foreign views), guard against unbounded allocations from untrusted size headers, verify offset boundaries before indexing, and validate memory alignment constraints; fix by capping pre-allocations, enforcing strict length bounds, and using checked slicing with safe fallbacks.

### Pillar 2: Concurrency, Cancellation & State Machine Lifecycles
<!-- Loops append bullets here. -->
- **Guaranteed cleanup on cancellation and error unwinding**: When managing asynchronous tasks, background workers, timers, or exclusive resource locks, ensure cancellation signals and error exits release held locks, terminate child routines, and resolve pending completion states; fix by acquiring resources through RAII guards or try-finally blocks and resetting cancellation latches upon session reuse.

### Pillar 3: Error Propagation, Diagnostics & No-Panic Invariants
<!-- Loops append bullets here. -->
- **Explicit error propagation and atomic state updates**: When handling recoverable operational errors or persisting state changes, return typed error representations instead of crashing, force-unwrapping, or discarding error contexts, and avoid non-atomic partial writes; fix by propagating descriptive error types with actionable recovery guidance and staging file modifications through temporary writes followed by atomic renames.

### Pillar 4: Multiplatform Portability & Cross-Binding Drift
<!-- Loops append bullets here. -->
- **Environment-independent contracts and schema synchronization**: When exposing public interfaces, serializing data, or bridging cross-language bindings, avoid hardcoding host-specific assumptions (such as absolute paths, endianness, line endings, or OS-dependent encodings) and prevent contract divergence; fix by deriving schemas from a single source of truth and abstracting platform idiosyncrasies behind portable facades.

### Pillar 5: Numerical Robustness & Boundary Validation
<!-- Loops append bullets here. -->
- **Checked arithmetic and domain boundary enforcement**: When performing mathematical calculations for array indexing, capacity sizing, pagination, or rate calculations, prevent integer overflow, wraparound, and division by zero, and ensure floating-point values are finite before branching; fix by using saturating or checked arithmetic operations and validating denominators and domain ranges at input boundaries.

### Pillar 6: Pipeline Completeness & Contract Faithfulness
<!-- Loops append bullets here. -->
- **License attribution completeness**: When a change adds or edits license files, verify the copyright notice names a holder (a bare year line attributes nobody and fails compliance checks), every documentation license claim resolves to a shipped file with matching terms, and standard license bodies stay verbatim; fix by naming the real holder and aligning doc links with the files on disk.

### Pillar 7: Performance, SIMD & Resource Efficiency
<!-- Loops append bullets here. -->
- **Hot-path allocation discipline and batch processing**: When processing repetitive loops, high-frequency request pipelines, or bulk data streams, avoid redundant memory allocations, unnecessary intermediate copies, and repeated fine-grained lock or network round-trips; fix by pre-allocating reusable scratch buffers, streaming large datasets, and batching fine-grained operations.

### Pillar 8: Code Simplification, Cleanup & Complexity Reduction
<!-- Loops append bullets here. -->
- **Linear control flow and premature abstraction removal**: When structuring decision logic or refactoring existing modules, avoid deeply nested conditionals, dead code branches, and unnecessary layers of indirection that obscure business logic; fix by replacing nested branches with early return guard clauses, deleting obsolete routines, and consolidating duplicate logic into canonical helpers.
