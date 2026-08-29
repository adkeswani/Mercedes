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
- Workout prescriptions that pin both the logical exercise ID and version.
- Active-relationship checks for new enrollments and workout assignments.
- Firestore rules and indexes for relationship-scoped mutations.

Compatibility behavior:

- Existing exercise documents resolve as synthetic version 1. Owners may run
  the idempotent repository backfill, while the first edit atomically preserves
  legacy content as version 1 and publishes the edit as version 2.
- The web app runs that owner-verified backfill automatically after sign-in;
  failures surface through the app entry error state rather than being ignored.
- Existing workout prescriptions without `exerciseVersion` resolve as version
  1; all newly published prescriptions use immutable, rule-validated
  subdocuments with an explicit version pin.
- Workout versions currently support up to nine prescriptions so every pin can
  be validated within Firestore's multi-document rules access limit.
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
- Typed workout blocks, shared organization metadata, provenance,
  subscriptions, and later implementation-sequence entities remain deferred.
