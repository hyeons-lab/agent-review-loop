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
   - Canonical `~/.agents/review-refinements.md` (default write target).
   - Legacy `~/.gemini/review-refinements.md` (read only).
   - Repo-local `.agents/review-refinements.md` (project specific).

## 2. The 8 Core Categories (Pillars)

Reviewers evaluate changes across these 8 areas. The `### Pillar N:` titles
below are exact: refinements files reuse them verbatim, and loops address
pillars by number. Never rename a pillar or add a 9th one.

### Pillar 1: Low-Level Safety, Alignment & Buffer Invariants

- Memory alignment and safe slice casting (checked casts with fallbacks over
  panic-prone direct casts on unaligned or memory-mapped buffers).
- Bounded reads and writes: capped stream decoding, guarded empty or
  zero-byte allocations, padded chunk remainders, and verified buffer
  extents before slicing across trust or language boundaries.

### Pillar 2: Concurrency, Cancellation & State Machine Lifecycles

- Cancellation and shutdown lifecycles: reset latches at session entry,
  resolve every pending promise on error paths, and tear down workers,
  timers, and leases without leaks or use-after-free.
- Contention and ordering: batch queries under one lock acquisition, bound
  IPC timeouts with graceful fallback, and keep monotonic sequences intact
  across restarts and handovers.

### Pillar 3: Error Propagation, Diagnostics & No-Panic Invariants

- No-panic runtime paths: return typed errors (`Result`, `?`, or the
  language equivalent) instead of force-unwrapping values that untrusted
  input can influence.
- Persistence and diagnostics: atomic file writes (temp file plus rename),
  explicit permission modes, and errors that name the failing resource and
  the recovery path.

### Pillar 4: Multiplatform Portability & Cross-Binding Drift

- Foreign binding sync: generated bindings (FFI, WASM, mobile, typed
  clients) regenerated and drift-checked whenever the source surface moves.
- Portable builds: stable toolchain features by default, feature-gated
  platform code, and no hardcoded page sizes, paths, or OS identities.

### Pillar 5: Numerical Robustness & Boundary Validation

- Finite, in-range arithmetic: finiteness checks on floats that feed
  decisions, nonzero positive denominators, and saturating or checked
  integer math on sizes, offsets, and capacities.
- Clamped boundaries: inputs and config values validated against the tables
  and buffers they index before use.

### Pillar 6: Pipeline Completeness & Contract Faithfulness

- End-to-end parameter fidelity: sampling, filtering, and config options
  forwarded unchanged through every pipeline stage to the kernel that
  honors them.
- Traversal and isolation guards: shell metacharacters, path escapes, and
  credential scopes contained at each stage boundary.

### Pillar 7: Performance, SIMD & Resource Efficiency

- Hot-path allocation discipline: pre-allocated and reused scratch buffers,
  eliminated staging copies, and vectorized kernels where the workload is
  regular.
- Right-sized dispatch: threaded or batched work split to amortize launch
  cost without starving interactive or priority lanes.

### Pillar 8: Code Simplification, Cleanup & Complexity Reduction

- Flattened structure: guard clauses over nested conditionals, standard
  combinators over manual loops, and no premature abstraction layers.
- Removed dead weight: deleted obsolete code, deduplicated boilerplate, and
  one canonical helper per repeated pattern.

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
   review in a different file.
4. **Theme clustering**: merge related micro-issues into one cohesive
   principle. Cap each loop run at 5 new or refined bullets.
5. **Multi-agent safety**: re-read the target file immediately before
   editing; keep bullets tool-agnostic (no agent, model, runtime, or tool
   names); add no signatures or date tags; append or refine only, never
   delete, reword wholesale, or reformat.
