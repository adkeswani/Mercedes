# Training Domain Model Design

> **Status:** Approved direction for implementation
>
> **Purpose:** Define the domain boundaries, lifecycle rules, ownership model,
> and synchronization behavior needed for reusable training content and
> athlete-specific delivery.

## 1. Goals

The model must support:

- Reusable exercise, workout, and program libraries.
- Top-down and bottom-up creation.
- Trainer-to-athlete assignment.
- Subscribed programs that receive future trainer updates.
- Independent copies that can be customized.
- Stable historical workouts and exercise details.
- Multiple concurrent programs per athlete.
- Flexible workout formats and exercise measurements.
- Persistent notes and instance-specific discussions.
- Clear trainer-client access boundaries.
- One responsive application with capability-based UX.

The model should keep synchronization and ownership rules predictable. The UI
must explain meaningful consequences, but users should not need to understand
the storage implementation.

## 2. Core Concepts

### 2.1 Content hierarchy

```text
Exercise
  -> Exercise Version
    -> Workout Template
      -> Workout Template Version
        -> Program Template
          -> Program Template Version
            -> Athlete Program Instance
              -> Scheduled Workout Instance
```

Trainers may start at any level:

- Create exercises and assemble them into a workout.
- Create a workout and create exercises without leaving the builder.
- Create a program and create its workouts and exercises in place.

Every exercise, workout, and program can be explicitly copied.

### 2.2 Logical objects and immutable versions

An exercise, workout, or program is a stable logical object with organizational
metadata. Execution-relevant changes create immutable versions.

Versions ensure that historical and assigned content can identify exactly what
was prescribed.

| Object | Stable/live fields | Versioned fields |
| --- | --- | --- |
| Exercise | ID, owner, tags, folder, archival state | Name, instructions, media, exercise type, measurement configuration, grading configuration |
| Workout | ID, owner, tags, folder, archival state | Name, format, ordered blocks, exercise-version references, prescriptions |
| Program | ID, owner, tags, folder, archival state | Name, description, ordered workouts, phase separators, relative schedule |

An explicit copy creates a new logical object and records provenance to its
source. Normal editing publishes a new version of the same logical object.

## 3. Principal Entities

### 3.1 Trainer-client relationship

`TrainerClientRelationship` represents the business relationship independently
of any program.

Required concepts:

- `trainerId`
- `athleteId`
- `status`: active or ended
- `startedAt`
- `endedAt`
- audit fields

This relationship controls:

- Whether the athlete appears in the trainer's client workspace.
- Whether the trainer may assign or update eligible content.
- Whether the athlete may access content exposed through the trainer.
- Whether subscriptions remain linked.

Program enrollment must not be used as a substitute for this relationship.

### 3.2 Exercise

`Exercise` is a trainer-owned logical library item.

Required concepts:

- Stable exercise ID.
- Trainer owner ID.
- Current version number.
- Tags and optional folder.
- Source provenance when copied.
- Archival and audit fields.

`ExerciseVersion` is immutable and contains:

- Display name.
- Instructions.
- Photos, video, and external media references.
- Exercise type.
- Measurement configuration.
- Grading configuration.
- Publication metadata.

Initial grading support should allow V-scale and trainer-defined gym colors.
The schema must be extensible to additional grading systems.

Exercises are global within the trainer's library. They are not duplicated into
per-athlete exercise libraries.

### 3.3 Workout template

`WorkoutTemplate` is a trainer-owned reusable workout definition.

Required concepts:

- Stable workout ID.
- Trainer owner ID.
- Current version number.
- Tags and optional folder.
- Source provenance when copied.
- Archival and audit fields.

`WorkoutTemplateVersion` is immutable and contains an ordered list of typed
workout blocks.

Each exercise occurrence must have a stable prescription/slot ID and reference:

- Exercise ID.
- Exercise version.
- Prescription and measurement settings.
- Position within the workout.

A stable slot ID is required because the same exercise may appear more than
once in a workout and results must map to the correct occurrence.

Workout format and training category are separate concepts. For example,
`strength` may be a category while `timedIntervals` is a format.

The block model must accommodate:

- Standard sets and repetitions.
- Duration and distance work.
- Timed intervals.
- Circuits.
- Climbing routes with grade and color.
- Future block types without redesigning the entire workout entity.

### 3.4 Program template

`ProgramTemplate` is a trainer-owned reusable program definition.

Required concepts:

- Stable program ID.
- Trainer owner ID.
- Current version number.
- Tags and optional folder.
- Source provenance when copied.
- Archival and audit fields.

`ProgramTemplateVersion` is immutable and contains an ordered sequence of:

- Workout references.
- Phase separators.

Phase separators are organizational labels only. They do not implement
progression or scheduling behavior. Trainers may freely reorder workouts and
phase separators.

Workout references pin a workout template version and contain their relative
schedule within the program.

An athlete may have multiple active program instances. There is no separate
main/add-on program concept.

### 3.5 Athlete program instance

`AthleteProgramInstance` represents a program delivered to one athlete. It is
owned by the athlete, while the assigning trainer retains limited permissions
during an active trainer-client relationship.

Required concepts:

- Athlete owner ID.
- Assigning trainer ID.
- Source program ID and source version.
- Relationship mode: subscribed or copied.
- Start date and derived expected end date.
- Lifecycle status.
- Link/unlink timestamps and reason.
- Audit fields.

#### Subscribed mode

A subscribed program remains linked to the trainer's template. New trainer
versions propagate to eligible future workout instances.

#### Copied mode

A copied program is independent. It does not receive future source-template
updates and may be customized freely.

The first structural customization of a subscribed program or workout converts
the affected subscribed content into an independent copy. The UI must explain
and confirm this before applying the edit.

The following actions are not structural customizations and do not convert a
subscription:

- Adding persistent notes.
- Creating or replying to comment threads.
- Adding reactions.
- Recording scheduling state.
- Recording completion data.

### 3.6 Scheduled workout instance

`ScheduledWorkoutInstance` contains both the athlete-specific prescription and
the completion state. Completion is not a separate top-level object.

Required concepts:

- Athlete owner ID.
- Assigning trainer ID.
- Parent program instance ID, when applicable.
- Source workout ID and version.
- Relationship mode.
- Scheduled date.
- Materialized workout blocks and exercise-version references.
- Status and completion timestamp.
- Per-slot results.
- RPE, duration, and athlete completion notes.
- Link/unlink metadata.
- Audit fields.

The materialized prescription allows the workout to become an independent,
stable historical record.

## 4. Subscription and Propagation Rules

### 4.1 Eligible propagation

A trainer's template update may propagate only when all of the following are
true:

- The program or workout remains subscribed.
- The trainer-client relationship is active.
- The workout is incomplete.
- The workout is scheduled for today or the future.

Past or completed workouts never change.

### 4.2 Propagation behavior

When a subscribed program publishes a new version:

1. Record the new immutable template version.
2. Find active subscribed program instances.
3. Reconcile only eligible current/future workout instances.
4. Create, update, reschedule, or cancel eligible instances to match the new
   version.
5. Preserve historical instances, completion data, notes, threads, and
   reactions.
6. Record the applied source version and propagation audit data.

Propagation should run in an idempotent server-side job. Re-running the same
source-version update must produce no additional changes.

### 4.3 Unlinking

Linked content retains its current materialized state and stops receiving
updates when:

- It is structurally customized and converted to a copy.
- Its workout is completed.
- Its workout becomes historical.
- The trainer-client relationship ends.

When a trainer-client relationship ends:

- Existing athlete content remains usable.
- Subscriptions unlink.
- No future template changes propagate.
- The athlete loses access to browse or subscribe to the trainer's library.

## 5. Ownership and Permissions

Every repository mutation and security rule must verify ownership and the
active relationship before writing.

### 5.1 Templates

- Trainer owns their exercise, workout, and program templates.
- Only the owner may publish structural versions or change organization.
- A copy is owned by its creator and does not grant mutation rights to the
  source.
- Future staff support may share template ownership, but is out of scope.

### 5.2 Athlete instances

- Athlete owns assigned program and workout instances.
- Assigning trainer may read the instance while the trainer-client
  relationship is active.
- Assigning trainer may update scheduling and prescribed content only while the
  workout is incomplete and current/future.
- Athlete controls completion results.
- Neither party may overwrite data authored by the other.
- After completion or the scheduled date passes, prescribed content and results
  are immutable.
- Trainer and athlete may continue participating in shared threads and
  reactions on historical content.

## 6. Visibility and Libraries

### 6.1 Trainer workspace

The trainer experience presents a folder-style workspace containing:

- Exercise templates.
- Workout templates.
- Program templates.
- Client workspaces.

Each client workspace contains:

- Subscribed programs.
- Independent program copies.
- Individually assigned workouts.
- Schedule and history.
- Results, notes, discussions, and messages.

Folders, tags, and saved views organize content but do not determine ownership
or authorization.

### 6.2 Athlete visibility

Athletes:

- See programs and workouts assigned or otherwise exposed to them.
- See the exercise details required by those visible workouts.
- Do not browse the trainer's complete exercise library.
- May access eligible program/workout library content only while the
  trainer-client relationship is active.

## 7. Notes, Threads, and Reactions

Persistent notes and instance discussions are separate concepts.

### 7.1 Persistent notes

`PersistentNote` attaches to a logical exercise, workout, or program rather than
to a version or instance.

Required concepts:

- Subject type and logical subject ID.
- Trainer-client context where applicable.
- Author ID.
- Visibility, such as private or shared.
- Note body.
- Audit fields.

Because the subject is logical, notes remain available across all versions and
instances. An athlete's squat rack-height note therefore follows that exercise
when it appears in future workouts.

### 7.2 Discussion threads

`DiscussionThread` attaches to a specific exercise slot, workout instance, or
program instance.

`ThreadMessage` contains:

- Thread ID.
- Author ID.
- Body and supported media references.
- Audit fields.

`MessageReaction` contains:

- Message ID.
- Reactor ID.
- Reaction type.
- Audit fields.

Athletes and trainers may create threads, reply, and react when they can view
the parent instance. Historical instances remain discussable.

## 8. Personal Bests and Activity

Exercise measurement configuration determines personal-best comparison.

Examples:

- Weight: greater is better.
- Repetitions: greater is better.
- Distance: greater is better.
- Duration: comparison direction is configured by the exercise; longer may be
  better for endurance while shorter may be better for timed completion.
- Climbing grade: compare using the configured grading system.

Workout completion, comments, reactions, personal bests, assignments, and
program lifecycle changes should emit activity events or update equivalent
read projections. Dashboard screens consume these projections rather than
reconstructing all activity from raw documents on every read.

## 9. Responsive Application Model

Desktop, mobile, and web use one application and one domain model.

- Role determines authorization.
- Device and selected web mode determine available presentation capabilities.
- Mobile emphasizes viewing, completion, and basic creation/updates.
- Full web/desktop mode provides complete library and builder workflows.
- Web may also present the restricted app-style view.

Capability restrictions are UX concerns and must not replace backend
authorization.

## 10. Stage 4 Model Impact

The existing Stage 4 model is a useful migration base rather than disposable
code. The following changes are required.

| Existing model | Required change |
| --- | --- |
| `UserProfile` | Keep as account identity. Do not encode trainer-client relationships or device capabilities on the profile. |
| `Enrollment` | Retain only for program access if still needed; add `TrainerClientRelationship` as the durable roster and authorization boundary. |
| `ExerciseTemplate` | Split into a logical exercise header and immutable exercise versions. Add explicit owner, tags, folder, provenance, and current version. |
| `WorkoutTemplate` | Add explicit owner, tags, folder, and provenance. Preserve immutable versions but replace flat prescriptions with typed blocks and stable slot IDs that pin exercise versions. |
| `Program` | Keep immutable versions and relative scheduling. Add tags and provenance; replace the workout-only list with ordered workout and phase-separator entries. |
| `WorkoutInstance` | Evolve into the athlete-owned materialized scheduled workout. Add relationship mode, unlink metadata, stable slot results, and stricter historical immutability. |
| `programAssignmentId` grouping | Replace or back with a first-class `AthleteProgramInstance` document containing lifecycle and subscription state. |
| `ExerciseNote` | Generalize into persistent notes keyed to logical exercise, workout, or program subjects with author and visibility. |
| `Comment` | Replace optional-scope inference with explicit instance subject type/ID and thread/message/reaction entities. |
| `WorkoutType` and `ExerciseMode` | Separate category, workout format, block type, measurement type, and grading configuration. |
| Program folders | Generalize organizational metadata so exercises, workouts, programs, and client workspace views use consistent folder/tag concepts. |

Repository serialization, providers, Firestore indexes, and security rules must
change with each migrated entity. Compatibility readers should treat existing
exercise documents as version 1 and existing assigned workouts as independent
materialized copies unless a safe subscription relationship can be proven.

## 11. Implementation Sequence

1. Add the trainer-client relationship and explicit ownership primitives.
2. Add exercise versioning and migrate existing exercises to version 1.
3. Add tags, folders, provenance, and shared library abstractions.
4. Introduce typed workout blocks and stable exercise slot IDs.
5. Adapt workout and program versions to the new references.
6. Add athlete program instances and explicit subscribed/copied modes.
7. Materialize scheduled workout instances and enforce historical immutability.
8. Implement server-side subscription propagation and unlinking.
9. Implement persistent notes, discussion threads, and reactions.
10. Build activity projections and dashboard queries.
11. Build responsive trainer libraries, client workspaces, and athlete flows.

Each step must include domain tests, repository tests, Firestore security-rule
tests, and any required backfill tests before the next step depends on it.

## 12. Deferred Details

The model intentionally leaves these extensible rather than blocking the first
implementation:

- Exact typed block payloads for every workout format.
- Complete climbing grading and gym-color schemas.
- The full personal-best comparator catalog.
- Search indexing and saved-view implementation.
- Native versus web capability presentation details.
- Staff sharing.
- Waiver-service integration.
- Payment-site account provisioning.
- YouTube and CSV import pipelines.

These additions must conform to the ownership, versioning, subscription, and
historical immutability rules defined above.
