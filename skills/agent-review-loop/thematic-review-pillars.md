# Thematic Review Pillars (Shared Base)

This document defines the **8 Core Thematic Pillars** (the defaults) and the
**self-improvement protocol** shared by every review loop that files
learnings into the refinements file (`agent-review-loop`,
`agent-review-report`, and `address-pr-comments`).

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
     `$REVIEW_REFINEMENTS_LEGACY=1` is set; skipped by default). Note that
     legacy entries follow pre-generalization pillar numbering (such as
     Buffer Safety and Numerical Robustness) rather than the canonical 8
     categories below.

   Standing rule: every bullet in the canonical file must help a review in a
   different repo on a different stack. Repo-specific lessons belong in the
   repo-local file.

## 2. The 8 Core Categories (Pillars)

Reviewers evaluate changes across these 8 areas. The `### Pillar N:` titles
below are exact: refinements files reuse them verbatim, and loops address
pillars by number. Never rename a pillar or add a 9th one.

### Pillar 1: Functional Correctness, Logic & Edge Cases

- Algorithmic and logic integrity: verify algorithm accuracy, control flow
  branching, and state mutation; prevent off-by-one errors, faulty boolean
  conditions, and unexpected calculation outputs.
- Edge-case and boundary robustness: guard against null, nil, or undefined
  references, empty collections, zero-length inputs, and boundary overflow;
  enforce explicit defaults and defensive lookups over unchecked access.

### Pillar 2: Security, Authentication & Input Sanitization

- Input containment and injection prevention: sanitize and parameterize all
  untrusted inputs entering shells, queries, file systems, deserializers, or
  template engines; reject path traversal and metacharacter escapes.
- Authentication and boundary authorization: enforce privilege boundaries,
  validate access credentials, avoid insecure direct object references, and
  ensure sensitive data and tokens are redacted from diagnostics and logs.

### Pillar 3: Concurrency, Asynchrony & Lifecycle Management

- Task cancellation and guaranteed cleanup: tie resource disposal to RAII drop
  guards, defer statements, or finally blocks; reset cancellation latches on
  session entry; resolve pending promises or futures on error unwinding; and
  terminate worker routines without leaks.
- Synchronization and contention discipline: avoid data races and deadlocks
  through clear lock hierarchy and minimal critical sections; enforce bounded
  timeouts with graceful fallbacks across external network, IPC, and service
  boundaries.

### Pillar 4: Error Handling, Resilience & Diagnostics

- Safe, typed error propagation: return typed, inspectable errors instead of
  force-unwrapping, throwing raw strings, panicking, or swallowing exceptions
  in runtime paths.
- Atomic persistence and diagnostic clarity: stage file and state mutations
  through temporary writes followed by atomic renames; emit actionable error
  messages that identify the failing resource and the recovery path.

### Pillar 5: Interface Contracts, API Design & Compatibility

- Contract parameter fidelity and encapsulation: ensure options, configurations,
  and context headers pass cleanly through architecture layers without silent
  dropping or defaulting surprises; keep public surfaces cohesive and minimal.
- Schema synchronization and backwards compatibility: derive schemas and
  cross-boundary bindings from a single source of truth; preserve backward
  compatibility or provide clear migration paths across API version shifts.

### Pillar 6: Performance, Resource Efficiency & Scalability

- Hot-path allocation and memory discipline: avoid unnecessary heap allocations,
  excessive object cloning, and intermediate buffer copies in throughput-critical
  paths; pre-allocate and reuse scratch buffers where workloads are regular.
- Workload batching and I/O efficiency: batch fine-grained database queries,
  file operations, and network calls; apply backpressure to incoming streams;
  and bound connection and thread pool growth.

### Pillar 7: Code Simplification, Clean Architecture & Maintainability

- Linear control flow and minimal indirection: favor early return guard clauses
  over deeply nested conditionals; avoid premature abstractions and excessive
  indirection that obscure business logic; use standard library idioms.
- Dead code elimination and canonical consolidation: remove obsolete code,
  unused dependencies, and redundant boilerplate; maintain one canonical
  helper per repeated pattern.

### Pillar 8: Testing, Observability & Verification Invariants

- Non-vacuous testing and regression coverage: ensure automated tests exercise
  actual behavior and fail when defects are introduced; prove test non-vacuity;
  cover boundary failure paths and regression scenarios.
- Observability and compliance verification: structure application telemetry,
  metrics, and audit logging to provide actionable operational insight; verify
  license attribution and compliance terms align with shipped code.

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
