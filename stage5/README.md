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
- First-class athlete-owned `AthleteProgramInstance` records with pinned source
  program versions, lifecycle dates/status, and explicit `subscribed` or
  `copied` relationship modes.
- Atomic, idempotent program materialization: the program instance and every
  scheduled workout are committed together, and each workout references the
  first-class instance while retaining the legacy assignment ID alias.
- Confirmation-gated subscription-to-copy conversion for structural
  customization, plus recoverable unlink-to-copy when a trainer-client
  relationship enters its `ending` state. New assignments are blocked before
  unlink batches run, and retries finish the transition to `ended`.
- Authoritative Cloud Function propagation for each newly published immutable
  program version. Active subscribed athlete program instances reconcile only
  current/future scheduled workouts by stable program-entry ID. Additions,
  removals, substitutions, ordering, schedule changes, and pinned workout
  versions are applied without touching historical/completed workouts or
  athlete-authored completion and communication data.
- Retry-safe propagation audit state on program versions and athlete program
  instances (`pending`, `running`, `complete`, or `failed`), including target
  and applied versions, attempt timestamps, errors, and mutation counts.
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
- Existing `programAssignmentId` groups remain readable. An athlete-owned,
  idempotent backfill creates conservative independent copies and adds
  `athleteProgramInstanceId` references without rewriting historical results.
- Legacy workouts without the immutable `scheduledAt` authorization field
  remain readable but cannot be structurally changed by clients; a trusted
  administrative migration is required before those records become mutable.
- Trainers may manage only current or future incomplete workouts while the
  relationship is active. Completed and past workouts remain historical;
  athletes must explicitly convert subscriptions before structural changes.
- Signed-in template reads remain compatible with Stage 4 while assigned
  workout detail resolves its pinned immutable workout/exercise versions;
  owner-only template writes are enforced.
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
- Legacy program entries without stable IDs resolve to deterministic
  `legacy-{sortOrder}` identities. New builder entries receive stable IDs before
  publication, and assigned workouts persist the ID and source order.
- Legacy athlete program instances without propagation fields read as
  `complete` at their recorded source version. Legacy assignment backfill
  remains conservative copied mode and is never enrolled into propagation.

Subscription propagation is server-authoritative: clients can request only a
`pending` job as part of the atomic program-version publish. They cannot mark a
job complete or mutate propagation audit fields. The retried Firestore create
trigger verifies program/workout ownership and the active trainer-client
relationship before every write. Ending or ended relationships, copied
instances, unlinked content, past workouts, and terminal workouts are skipped.
The Functions manifest adds only the repository test command and does not add,
remove, pin, or update any package, so the license notices and tooling
version/lock inventories are intentionally unchanged.

## Browser login smoke test

Stage 5 has one intentionally narrow browser integration test. It starts the
Flutter web app in Chrome against local Firebase Auth and Firestore emulators,
signs in through the real login and bootstrap path, and verifies that routing
reaches the authenticated app entry. It does not assert Firestore application
reads or writes and is not a broad UX test.

Prerequisites:

- Flutter 3.41.2 with Chrome installed.
- ChromeDriver matching the installed Chrome version, available on `PATH` or
  through the `CHROMEDRIVER_PATH` environment variable.
- Firebase CLI 15.15.0 and a Java runtime supported by the Firestore emulator.
- Windows Developer Mode enabled before the initial `flutter pub get`, because
  Flutter plugins require symbolic-link support.
- Ports 9099 (Auth) and 8080 (Firestore) available locally.

From the repository root, run:

```powershell
.\stage5\tool\run-browser-login-smoke.ps1
```

The script starts clean emulators, creates
`browser-smoke@mercedes.test` with a non-secret deterministic password, seeds
only the profile needed for bootstrap, runs the browser test in Chrome's
desktop test viewport, and shuts the emulators down. No real Firebase or Google
credentials are required.
Google OAuth is deliberately not automated because its external consent UI is
not deterministic in the Firebase Auth emulator. Instead, the local-login
button is compiled in only when explicit browser-smoke and emulator flags are
present in a debug build; release builds cannot enable it.

The desktop-sized viewport is the current smoke-test baseline. After navigation
and responsive layouts stabilize, add a phone-sized viewport (for example,
390x844) as a separate run of the same authentication assertion rather than
adding UX assertions to this smoke test.

Full browser E2E remains deferred until the UX stabilizes. That later suite
will cover trainer/athlete contexts, relationships, enrollments, assignment,
propagation, immutable history, and responsive workflows with isolated seeded
data and failure artifacts.
