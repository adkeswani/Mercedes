# Stage 5

Stage 5 starts the approved training domain model migration while preserving
the Stage 4 application behavior.

Implemented in this slice:

- A responsive authenticated web shell that separates athlete and trainer
  workspaces without introducing roles, claims, permissions, or identity
  changes. Every signed-in user can switch modes from the top-right segmented
  control.
- Route-driven web context under `/athlete/...` and `/trainer/...`. Direct links
  select the corresponding workspace, while the root route restores the last
  browser selection from `localStorage` and otherwise defaults to Athlete.
- Athlete navigation for Today, My calendar, My programs, Workout history,
  Progress, and Messages. Today reuses the current training experience. My
  calendar now uses the athlete-owned date-range query directly instead of
  entering the trainer calendar's enrollment and legacy-migration flow.
- A dedicated My programs workspace backed by signed-in-athlete
  `AthleteProgramInstance` records. It runs the existing conservative legacy
  assignment backfill and renders loading, empty, error, active, completed,
  and cancelled states without creating a parallel enrollment model.
- A Workout history workspace backed by the signed-in athlete's immutable
  terminal records and overdue workout instances, using the existing
  `(athleteId, scheduledDate)` Firestore index.
- An accessible desktop account identity beside the Athlete/Trainer switch.
  It prefers the profile display name, then username, authentication display
  name, email, and finally a non-sensitive signed-in fallback. The text is
  constrained and ellipsized so the desktop header remains responsive.
- Trainer navigation for Dashboard, Clients, Exercise library, Workout library,
  Program library, and Calendar & assignments. Existing roster, library, and
  trainer calendar screens remain wired to their natural destinations.
- Reusable, descriptive empty destinations for dashboard, progress, and
  messages while those focused experiences are deferred.
- The existing compact/mobile home and navigation remain unchanged below the
  desktop breakpoint. Login and onboarding do not expose the workspace switch.
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

Stage 5 has browser integration coverage that starts the Flutter web app in
Chrome against local Firebase Auth and Firestore emulators and signs in through
the real login and bootstrap path. Both identities verify their accessible
header identity. The athlete run also navigates to and verifies seeded
first-class program instance data, completed workout history, and the
athlete-owned calendar query before capturing each surface.

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

The script starts clean emulators, creates two non-secret deterministic
identities, seeds their bootstrap profiles, active trainer-athlete
relationship, an athlete program instance, a current calendar workout, and a
completed historical workout. It then runs the selected identity in Chrome's
1280x800 desktop viewport and shuts the emulators down:

| Role | Emulator email | Emulator password |
| --- | --- | --- |
| Trainer | `browser-smoke-trainer@mercedes.test` | `BrowserSmokeTrainer123!` |
| Athlete | `browser-smoke-athlete@mercedes.test` | `BrowserSmokeAthlete123!` |

Run the same login/bootstrap assertion as the athlete with:

```powershell
.\stage5\tool\run-browser-login-smoke.ps1 -Identity athlete
```

Each run seeds both identities and the relationship, signs in only the
selected identity, and opens that run's workspace route. Identity selection is
test context only: it does not represent a role or permission.
No real Firebase or Google credentials are required.
Google OAuth is deliberately not automated because its external consent UI is
not deterministic in the Firebase Auth emulator. Instead, the local-login
button is compiled in only when explicit browser-smoke and emulator flags are
present in a debug build; release builds cannot enable it.

### Screenshot artifacts

After the real login, route, workspace, identity, and data assertions pass, the
runner captures deterministic 1280x800 PNGs under the selected artifact
directory. A direct athlete integration run produces:

```text
stage5/test-artifacts/browser-login/
  athlete-header-identity.png
  athlete-my-programs.png
  athlete-workout-history.png
  athlete-calendar.png
```

The trainer run produces `trainer-header-identity.png`. Screenshots are
diagnostic artifacts rather than golden assertions. The runner drives the real
Flutter application through ChromeDriver and the emulator-only login seam.

On one Windows screenshot-based run, Chrome appeared to require a manual click
or foreground focus before the test progressed. This is an intermittent
observation to investigate, not a confirmed prerequisite or permanent
workaround. Follow-up should reproduce whether foreground focus is actually
required, inspect ChromeDriver window activation and screenshot timing, and
automate focus only if that need is proven.

## Release authorization contract

Stage 5 web releases must deploy the client and its Firestore authorization
contract as one ordered release. Pass an explicit Firebase project ID or CLI
alias:

```powershell
.\deploy.ps1 -Target web -StageDir stage5 -Project mercedes-app-11ce2
```

The script deploys Firestore rules and indexes first, waits until every
composite index in `firestore.indexes.json` reports `READY`, and deploys
Hosting only after that gate succeeds. `scripts/verify-web-deploy-contract.ps1`
is part of Stage 5 validation and fails if this ordering, the explicit project
requirement, or the repository Firestore configuration is removed. A
Hosting-only release is not a complete Stage 5 release because new client
queries can depend on newer rules and composite indexes.

Authorization coverage is layered:

1. Firestore emulator tests execute the exact Calendar, My Programs, workout
   history, and legacy-backfill query shapes. Fixtures include modern records,
   legacy records missing newer optional fields, and another athlete's data;
   own-athlete queries must succeed while cross-athlete queries must fail.
2. Stage validation checks the combined deployment contract above. Release
   operators must select the intended Firebase project explicitly and review
   the active alias before deploying.
3. A deployed-environment canary should exercise login, Calendar, My Programs,
   and workout history using dedicated non-personal trainer and athlete
   accounts plus deterministic synthetic documents. Use a reserved
   `release-canary-` ID namespace, delete or overwrite that namespace on each
   run, store credentials only in the release system's secret store, and never
   read or mutate real user data. Run it manually as a staging promotion gate
   first; move it into CI after staging project aliases and protected secrets
   are configured.

Firebase environments should be separate projects for development, staging,
and production rather than Hosting preview channels sharing one backend. Add
explicit CLI aliases such as `dev`, `staging`, and `prod`, seed only synthetic
Auth/Firestore data in staging, deploy the full Hosting/rules/index bundle to
staging, run the canary, and then promote the same commit and configuration to
production with an explicit `--project` or selected alias. Creating those
projects, aliases, accounts, and secrets is intentionally deferred.

Screenshots remain useful diagnostics for layout and identity rendering, but
they are supplemental: they cannot establish that deployed rules and indexes
match the client query contract.

## Complete stage validation

Copilot's repository-local stage completion skill lives at
`.github/skills/stage-completion-testing/SKILL.md`. Its validation entry point
automatically runs the full Flutter suite, analyzer, Firestore rules suite, and
the browser login smoke for both emulator identities:

```powershell
.\scripts\run-stage-validation.ps1 -Stage stage5
```

The script writes browser output to a unique
`stage5/test-artifacts/stage-validation/<UTC timestamp>-<run ID>/` directory
and prints that absolute directory plus every artifact path before it exits,
including on failure. Direct browser-smoke commands continue to use the
stable `stage5/test-artifacts/browser-login/` paths above.

The desktop-sized viewport is the current smoke-test baseline. After navigation
and responsive layouts stabilize further, add a phone-sized viewport (for
example, 390x844) as a separate run of the same authentication assertion rather
than adding UX assertions to this smoke test.

Full browser E2E remains deferred until the UX stabilizes. That later suite
will cover trainer/athlete contexts, relationships, enrollments, assignment,
propagation, immutable history, and responsive workflows with isolated seeded
data and failure artifacts.

## Web workspace follow-ups

Trainer dashboard aggregation, athlete progress reporting, and messaging
remain polished empty destinations. My programs is currently a read-only
instance list and Workout history is a read-only chronological list; existing
detail and completion routes remain available. Detail and edit flows continue
to use their flat Stage 4-compatible routes, so existing deep links and mobile
navigation remain unchanged.
