# Stage 5

Stage 5 starts the approved training domain model migration while preserving
the Stage 4 application behavior.

Implemented in this slice:

- `TrainerClientRelationship` as the durable trainer roster and authorization
  boundary.
- Trainer-owned relationship lifecycle operations with active and ended
  states.
- Explicit `ownerId` fields for exercise and workout templates.
- Stable logical exercise headers with immutable execution-content versions.
- Immutable typed workout blocks for standard exercise work, timed intervals,
  circuits, and climbing routes.
- Stable exercise-slot IDs that pin both the logical exercise ID and immutable
  exercise version for every occurrence.
- Workout completion actuals keyed by slot ID so repeated exercises are
  unambiguous.
- Shared stable tags, type-scoped flat folders, and immutable copy provenance
  for exercise, workout, and program headers.
- A common library metadata/folder abstraction used by all three template
  repositories without changing the current program-folder UX.
- Active-relationship checks for new enrollments and workout assignments.
- Firestore rules and indexes for relationship-scoped mutations.

Compatibility behavior:

- Existing exercise documents resolve as synthetic version 1. Owners may run
  the idempotent repository backfill, while the first edit atomically preserves
  legacy content as version 1 and publishes the edit as version 2.
- The web app runs that owner-verified backfill automatically after sign-in;
  failures surface through the app entry error state rather than being ignored.
- Loading the roster materializes missing durable trainer-client relationships
  from active legacy enrollments. The owner-scoped migration is idempotent,
  excludes personal self-enrollments, tolerates missing or later-changed program
  headers, and never reactivates an explicitly ended relationship. Migration
  failures stay within the roster instead of blocking sign-in.
- Existing array-backed and prescription-subcollection workout versions resolve
  as standard exercise blocks. Missing exercise versions resolve as version 1,
  and deterministic legacy slot IDs use array position or the persisted
  prescription order so old occurrences remain stable without rewriting
  immutable versions.
- New typed versions stage an immutable manifest plus stable-ID block and slot
  children, then atomically seal the complete snapshot and advance the template
  header. Firestore rules validate manifest ID uniqueness, block cardinality,
  completeness, and each owner-scoped exercise-version pin.
- Workout versions currently support up to nine blocks and nine exercise slots.
- Existing list-backed completion actuals remain readable. Athlete-owned
  migration maps unique exercises, and complete repeated-exercise result sets,
  to pinned slot IDs; ambiguous partial repeated-exercise results are rejected
  rather than guessed.
- New and edited completions persist immutable-addressed
  `slotResults/{slotId}` documents. Repository ownership checks require the
  instance athlete, completion transitions are transactional, and Firestore
  rules require every result to match both the parent result index and pinned
  workout slot. Legacy synthesized slot IDs and Stage 4 list writes remain
  readable and migratable.
- Existing exercise and workout documents without `ownerId` derive ownership
  from `createdBy`; owner mutations backfill `ownerId`.
- Owner library queries remain keyed by `createdBy` so existing Stage 4
  documents remain visible.
- Existing enrollments and assigned content remain readable after a
  relationship ends, but new assignments require an active relationship.
- Signed-in template reads remain compatible with Stage 4 until scheduled
  workouts are materialized in a later sequence step; owner-only template
  writes are enforced now.
- Exercise notes remain keyed to the stable logical exercise ID, so they follow
  the exercise across versions.
- Existing headers without library metadata resolve with empty tags, no folder,
  and no provenance. The next owner organization mutation writes the new fields
  without rewriting immutable template versions.
- Existing untyped `programFolders` remain program folders. The collection name
  and IDs are retained for compatibility, while new folders carry an
  `itemType` discriminator and cannot be assigned across owners or types.
- Copy operations atomically record source template ID, source owner, pinned
  source version, timestamp, and copier. Provenance cannot be changed later.
- Athlete program instances, subscriptions, propagation, and full scheduled
  workout materialization remain deferred to later implementation steps.
