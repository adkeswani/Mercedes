# Stage 5

Stage 5 starts the approved training domain model migration while preserving
the Stage 4 application behavior.

Implemented in this slice:

- `TrainerClientRelationship` as the durable trainer roster and authorization
  boundary.
- Trainer-owned relationship lifecycle operations with active and ended
  states.
- Explicit `ownerId` fields for exercise and workout templates.
- Active-relationship checks for new enrollments and workout assignments.
- Firestore rules and indexes for relationship-scoped mutations.

Compatibility behavior:

- Existing exercise and workout documents without `ownerId` derive ownership
  from `createdBy` when read.
- The first owner mutation writes `ownerId`, providing an incremental backfill.
- Owner library queries remain keyed by `createdBy` so existing Stage 4
  documents remain visible.
- Existing enrollments and assigned content remain readable after a
  relationship ends, but new assignments require an active relationship.
- Signed-in template reads remain compatible with Stage 4 until scheduled
  workouts are materialized in a later sequence step; owner-only template
  writes are enforced now.
- Exercise versioning, typed workout blocks, provenance, subscriptions, and
  later implementation-sequence entities remain intentionally deferred.
