# Thematic Review Pillars (Shared Base)

This document defines the **8 Core Thematic Pillars** (the defaults) and the
**self-improvement protocol** shared by every review loop that files
learnings into the refinements file (`review-fix-loop` in any runtime,
`review-and-report`, and `address-pr-comments`).

It travels with the skill and stays stable. Automated learning never edits
this file; it writes to the Tier 2 file instead.

## 1. Two-Tier Architecture: Defaults vs. Shared Refinements

1. **Base pillars** (this file, next to `SKILL.md`):
   The foundational 8 categories and their general invariant definitions.
   Baseline fallback for every review. Stable across loops and runtimes.

2. **Shared refinements** (evolving, multi-agent):
   Concrete patterns, project-specific invariants, and failure modes
   synthesized from real reviews. Resolution order (read every file that
   exists; the more specific file wins a direct conflict):
   - `$REVIEW_REFINEMENTS_FILE` when set (explicit override).
   - Repo-local `.agents/review-refinements.md` (project-specific invariants).
   - Canonical `~/.agents/review-refinements.md` (default write target).
   - Legacy `~/.gemini/review-refinements.md` (read only when
     `$REVIEW_REFINEMENTS_LEGACY=1` is set; skipped by default).

   Standing rule: every bullet in the canonical file must help a review in a
   different repo on a different stack. Repo-specific lessons belong in the
   repo-local file.

## 2. The 8 Core Categories (Pillars)

Reviewers evaluate changes across these 8 areas. The `### Pillar N:` titles
below are exact: refinements files reuse them verbatim, and loops address
pillars by number. Never rename a pillar or add a 9th one.

### Pillar 1: Low-Level Safety, Alignment & Buffer Invariants

- Memory alignment and safe casting: validate memory alignment, size, and
  layout invariants before reading or transmuting raw buffers (e.g. mmap,
  network packets, serialized payloads); use checked casting helpers or safe
  parsers with fallbacks over unchecked direct casts.
- Bounded reads, writes, and buffer indexing: enforce capped stream decoding,
  verified buffer extents before slicing across trust boundaries, and guarded
  zero-byte or empty allocation edge cases to prevent out-of-bounds indexing,
  buffer overflows, and memory exhaustion.

### Pillar 2: Concurrency, Cancellation & State Machine Lifecycles

- Cancellation and resource cleanup: tie cleanup to RAII drop guards, defer
  statements, or finally blocks; reset cancellation latches on session entry;
  resolve all pending futures or promises on error paths; and terminate
  workers, timers, and connections without leaks or use-after-free.
- Contention and synchronization: minimize lock hold durations (batching
  queries where feasible); enforce explicit timeouts with graceful fallbacks
  on external IPC, socket, and service boundaries; and preserve monotonic
  sequence invariants across restarts and handovers.

### Pillar 3: Error Propagation, Diagnostics & No-Panic Invariants

- Safe error propagation: return typed, inspectable errors (`Result`, error
  objects, or the language equivalent) instead of force-unwrapping, panicking,
  or swallowing failures in runtime paths processing untrusted or dynamic input.
- Diagnostics and atomic persistence: stage file modifications through
  temporary writes followed by atomic renames; enforce explicit permissions;
  redact credentials from logs; and emit actionable diagnostic messages naming
  the failing resource and recovery path.

### Pillar 4: Multiplatform Portability & Cross-Binding Drift

- Cross-boundary interface sync: keep generated bindings (e.g. FFI, WASM,
  mobile bridges, typed clients) and shared schemas synchronized with source
  definitions; detect drift automatically in validation checks.
- Portable builds and environment independence: rely on stable toolchain
  features; feature-gate platform-specific logic; avoid hardcoding paths,
  endianness, page sizes, line endings, or OS identities.

### Pillar 5: Numerical Robustness & Boundary Validation

- Arithmetic safety and precision: verify floating-point values for finiteness
  before branching; guard against division by zero; use checked, saturating, or
  widened integer arithmetic for sizes, offsets, and capacities.
- Boundary and domain validation: validate numeric configurations, pagination
  parameters, and index arguments against the bounds of backing tables and
  buffers at entry boundaries.

### Pillar 6: Pipeline Completeness & Contract Faithfulness

- End-to-end parameter fidelity: pass options, flags, filters, and context
  metadata unchanged through each pipeline layer to the underlying execution
  handler that honors them.
- Traversal and containment guards: contain shell metacharacters, path
  escapes, query delimiters, and credential scopes at every boundary.

### Pillar 7: Performance, SIMD & Resource Efficiency

- Hot-path allocation discipline: reuse scratch buffers, eliminate unnecessary
  intermediate copies or staging allocations, and apply data parallelism or
  vectorization (e.g. SIMD) where workloads are uniform.
- Right-sized dispatch and scheduling: batch fine-grained operations to amortize
  overhead, apply backpressure to incoming streams, and maintain fairness
  between interactive requests and background tasks.

### Pillar 8: Code Simplification, Cleanup & Complexity Reduction

- Flattened structure and clear control flow: prefer early guard clauses over
  nested conditionals, leverage standard library combinators, and avoid
  premature abstraction layers or needless indirection.
- Removed dead weight and canonical helpers: delete obsolete code, unused
  branches, and duplicate boilerplate, maintaining one canonical helper per
  repeated pattern.

## 3. Self-Improvement Protocol

When a review loop learns a recurring pattern worth keeping:

1. **Target**: file it per the write-target order in section 1 (override,
   then repo-local for repo-specific lessons, creating that file when it is
   missing, else canonical). Never write the legacy path. Never edit this
   base file or any skill definition.
2. **Subsumption**: map the pattern into one of the 8 pillars. Extend an
   overlapping bullet instead of adding a sibling.
3. **Generalization**: abstract away file names, line numbers, and variable
   names. State trigger, hazard, and fix shape so the bullet helps a future
   review in a different file. Standing rule for canonical: the bullet must
   help a review in a different repo on a different stack; if it cannot be
   stated that generally, abstract it or file it repo-local.
4. **Theme clustering**: merge related micro-issues into one cohesive
   principle. Cap each loop run at 5 new or refined bullets.
5. **Multi-agent safety**: re-read the target file immediately before
   editing; keep bullets tool-agnostic (no agent, model, runtime, or tool
   names); add no signatures or date tags; append or refine only, never
   delete, reword wholesale, or reformat.
