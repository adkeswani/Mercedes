# MVP Architecture & Delivery Plan (v0.9)

## Core Architecture to Define First

### Roles
- Account (base identity)
- Program Owner (per-program role)
- Athlete (per-program role)
- Optional Admin

### Main Entities
- Workout Program (supports owner-assignable programs and athlete-personal non-assignable programs)
- Exercise Template (reusable exercise definition with video + instructions)
- Workout Template (reusable workout definition; may contain child Workout Templates for nesting, e.g. a "Warmup" sub-workout inside a "Full Session")
- Program-to-Workout Mapping (ordered list)
- Workout-to-Exercise Mapping (ordered list + prescription fields such as sets/reps/weight)
- Workout-to-Workout Mapping (ordered list; allows a Workout Template to include child Workout Templates)
- Program Enrollment (manual access grant; includes `addedAt` and nullable `removedAt` timestamps)
- Program Schedule (assignment of workouts to calendar dates)
- Workout Type (classification tag: e.g. limit, power, endurance for climbing; lower, upper, full_body for strength)
- Workout Instance (user completion record; includes RPE and duration)
- Program Direct Message Thread (athlete↔program owner conversation, not tied to a workout instance)
- Workout Instance Comments (owner + user replies)
- Program Forum (threads + replies)

## Auth / SSO Strategy

- Implement Google Sign-In now (Android).
- Add Apple Sign-In support in the backend model from day one (even if hidden on Android UI).
- On iOS launch, enable Apple Sign-In in the UI immediately to satisfy platform expectations.

## Roadmap

1. [MVP] Foundation planning (hard-to-change architecture): finalize auth model, role/ACL boundaries, enrollment lifecycle fields, and versioning/audit requirements before feature build-out.
2. [MVP] Workout plan creation: exercise templates, workout templates, program structure, versioned publishing, owner program copy, and athlete personal program creation with copy + nesting + day assignment parity.
3. [MVP] Auth + athlete assignment: sign-in, role model, enrollment, and schedule assignment to athletes.
4. [MVP] Load/difficulty model: RPE + duration logging, workout-type-based weighting, dashboard load summaries, and athlete download/export of workout + load data.
5. [MVP] Community features (core): direct athlete↔owner messaging and private workout comments.
6. [Post-MVP] Community features (forum): program-level forum with reply notifications and athlete download/export of community conversation data.
7. [Post-MVP] Marketplace and access lifecycle: program discovery, durations, consent/waiver tracking, expiry notifications, and automatic enrollment removal.
8. [Post-MVP] Group workouts/plans: shared group progress, completion visibility, and group comments visible to members of the same group.

### Exit Criteria by Area

1. Foundation planning is complete when auth, roles, ACL scoping, enrollment lifecycle fields (`addedAt`/`removedAt`), template versioning, and audit-field requirements are documented as locked constraints for implementation.
2. Workout plan creation is complete when owners can create/edit/publish versioned programs, copy their own programs, build reusable workouts/exercises, assign workout-type tags without data-model rewrites, and athletes can create personal programs with equivalent builder capabilities (copy, workout nesting, day assignment) that remain non-assignable.
3. Auth + athlete assignment is complete when sign-in works on target platforms, role-scoped ACL checks are enforced, athlete enrollment writes `addedAt`, and date-based scheduling creates workout instances reliably.
4. Load/difficulty model is complete when required RPE + duration are captured on completion, load points are computed/stored server-side with versioning, dashboard widgets return correct weekly/type/bucket summaries, and athletes can export/download their workout + load history.
5. Community features (core) are complete when direct athlete↔owner messaging and private workout comments are live with correct per-program visibility and access control.
6. Community features (forum) are complete when program-level forum threads/replies and reply notifications are live with correct per-program visibility, and athletes can export/download their community conversation data.
7. Marketplace and access lifecycle is complete when program discovery is usable, duration-based access rules are enforced, consent/waiver status is tracked, pre-expiry notifications are sent, and removals write `removedAt`.
8. Group workouts/plans is complete when owners can run shared group plans, members can see group completion status appropriately, and group comments are visible to other members of the same group with role/privacy boundaries enforced.

## Important Design Decisions Now (to Avoid Rewrites)

- Keep `Workout Template` separate from `Workout Instance`.
- Allow the same person to be both a program owner and an athlete (role is contextual per program).
- Use role-based access checks on every read/write.
- Enforce per-program access control lists (ACL) so ownership and membership are scoped at the program level.
- Support owner-assigned access by username lookup, with the owner only seeing usernames during assignment.
- Version workout templates so old assigned programs remain stable.
- Allow program owners to copy their own programs as a starting point for new variants.
- Allow athletes to create personal programs with the same builder capabilities as owners (including copy, workout nesting, and day assignment), but only users acting as program owners can create assignable programs.
- Allow owners to define exercises (video + instructions) and assemble them into workout programs with program/workout-level prescriptions.
- Add audit fields (`createdBy`, `assignedBy`, timestamps) everywhere.
- Record program enrollment lifecycle timestamps for every athlete-program link (`addedAt`, `removedAt`).
- Support Workout Template nesting: the data model allows infinite depth (self-referential parent); the MVP UI supports one level of nesting (parent → children).

## Permissions & Visibility Rules

### Program Types

- **Owner-assignable program**: created by a user acting as Program Owner; can enroll/assign athletes under per-program ACL rules.
- **Athlete-personal program**: created by an athlete for self-use only; supports copy, workout nesting, and day assignment, but cannot enroll, assign, or expose the program to other users.

### Role Permissions (MVP)

- **Program Owner**
	- Can create, edit, publish, archive, and copy their own assignable programs.
	- Can enroll/remove athletes for programs they own (writes `addedAt`/`removedAt`).
	- Can assign schedules and view roster/adherence/load for their programs.
	- Can read/reply in program-level direct message threads with enrolled athletes.
	- Can read/reply in workout-instance comments for athletes assigned to their program.

- **Athlete**
	- Can view and complete workouts for programs where they are actively enrolled.
	- Can edit own workout-instance actuals/notes and required RPE/duration fields.
	- Can create and manage personal non-assignable programs for self-use.
	- Can copy personal programs, use workout nesting, and assign workouts to days within personal programs.
	- Can send/read/reply in program-level direct message threads with the program owner.
	- Can read/reply in their own workout-instance comments with the program owner.

### Visibility Rules (MVP)

- Program owners can view only data for programs they own.
- Athletes can view only data for programs where they are actively enrolled, plus their own personal programs.
- Athletes cannot see other athletes' private workout-instance comments.
- Program-level direct messages are visible only to the specific athlete and the owning program owner for that program.
- Athlete personal programs are visible only to the creating athlete and are not discoverable or assignable.

### Visibility Rules (Post-MVP)

- Program forum visibility is scoped to program membership and ownership ACL.
- Group comments are visible to members of the same group plan and relevant program owners, but not to non-members.

## Intensity & Load Model

### Workout Type Taxonomy

Workout type classifies what a session trains. The coach sets the workout type on the Workout Template, and logged instances inherit that assigned type.

Climbing types: limit, power, power_endurance, endurance, skill, mobility, cardio
Strength types: lower, upper, full_body, pull, push, legs, core, conditioning

### RPE (Rate of Perceived Exertion)

Athletes log a 1–10 RPE per workout instance. This captures subjective intensity.

### Load Points Formula (v1)

LoadPoints = TypeWeight × Effort × DurationModifier

- **TypeWeight** — fixed per workout type (e.g. limit = 5, endurance = 2, strength defaults to 3).
- **Effort** — RPE mapped to 1–5 (RPE 1–2 → 1, 3–4 → 2, 5–6 → 3, 7–8 → 4, 9–10 → 5).
- **DurationModifier** — <30 min → 0.75, 30–75 min → 1.0, >75 min → 1.25.

### TypeWeight Mappings (v1)

Climbing: limit=5, power=4, power_endurance=4, endurance=2, skill=2, cardio=2, mobility=1
Strength: lower=4, legs=4, upper=3, full_body=3, push=3, pull=3, core=2, conditioning=2

### Dashboard Widgets (Load Model)

1. **Weekly Total Load** — sum of LoadPoints for the current week, with change vs prior week.
2. **Type Breakdown** — pie/bar chart by workout type.
3. **Hard / Medium / Easy** — session count by LoadPoints bucket (easy ≤ 6, medium 7–12, hard ≥ 13).

### Load Model Decisions

- Store load model version alongside computed values so historical data stays stable if the formula changes.
- Compute load points on save (server-side) and store as a materialized field for fast dashboard queries.
- Provide athlete self-service export for workout + load data (JSON baseline; CSV optional for workout logs).

## Decision Log

- Create workout instances at schedule time.
- Use date-only assignment in MVP (no recurrence yet).
- Use athlete local timezone for day boundaries and due-date behavior.
- Allow athletes to adjust sets/reps/weight per workout instance.
- Athletes log RPE (1–10) and duration per workout instance; these are required for load computation.
- Coach sets the workout type on the Workout Template; athletes cannot override workout type when completing an instance.
- Program owners can copy their own programs; copied programs inherit structure and templates as a new editable draft.
- Athletes may create personal programs for self-use only; athlete-created programs cannot be assigned to other users.
- Athlete personal programs support the same builder actions as owner programs (copy, workout nesting, day assignment) but remain self-use and non-assignable.
- Load points are computed server-side on save using a versioned formula (TypeWeight × Effort × DurationModifier).
- Support a direct athlete↔program-owner message thread at program scope (outside workout instances), reusing comment/thread primitives.
- Keep workout-instance comments private to assigned athlete and program owner; allow edits.
- Auto-update all uncompleted scheduled items to the latest workout template version.
- Mark overdue workouts as missed and keep the original scheduled date.
- Allow assignment by exact username only, with user-controlled opt-in discoverability.
- Persist program enrollment lifecycle timestamps (`addedAt` on enrollment creation, `removedAt` on access removal).

## Athlete Experience Requirements

- [MVP] Personal planning: athletes can create and manage personal programs that are visible only to themselves and cannot be assigned to others.
- [MVP] Personal builder parity: athlete personal programs support copy, workout nesting, and day assignment like owner-created programs.
- [MVP] Daily clarity: a clear "Today" view showing due, upcoming, and missed workouts.
- [MVP] Calendar usability: visible schedule by day and clear status (scheduled, completed, missed).
- [MVP] Data trust: athletes can see who can access their workout data and comment threads.
- [MVP] Flexible logging: capture actual sets/reps/weight, RPE (1–10), duration, and athlete notes per workout instance.
- [MVP] Progress visibility: load trends (weekly total, type distribution, hard/medium/easy), consistency streaks, and personal bests.
- [MVP] Data portability (training): athletes can download/export their workout history and load metrics.
- [MVP] Communication clarity: direct message thread with program owner is available outside workouts.
- [MVP] Communication clarity: private owner↔athlete workout-instance comments are available.
- [Post-MVP] Communication clarity: program-level forum is available with reply notifications.
- [Post-MVP] Data portability (community): athletes can download/export their direct messages, workout comments, and forum contributions.
- [Post-MVP] Scheduling flexibility: athlete reschedule request flow and conflict handling.
- [Post-MVP] Reliability: offline draft logging and media-performance optimizations.
- [Post-MVP] Safety support: contraindication notes, substitutions, and report-exercise-issue flow.

## Program Owner Experience Requirements

- [MVP] Program reuse: program owners can copy their own programs to create new assignable variants faster.
- [MVP] Template governance basics: draft/publish/archive states and change-impact preview before propagating template updates.
- [MVP] Assignment operations: support bulk assignment and cohort/tag-based assignment.
- [MVP] Athlete intake visibility: view athlete goals, experience level, equipment constraints, and schedule constraints before assignment.
- [MVP] Adherence visibility: completion %, missed sessions, streak breaks, and at-risk athlete indicators.
- [MVP] Owner inbox visibility: direct athlete messages are visible and replyable at program scope.
- [Post-MVP] Safety controls: contraindication-aware substitutions, required warmup/cooldown rules, and exercise issue escalation.

### Athlete Decision Log

- [MVP] Personal programs are self-use only and non-assignable, with builder parity (copy, workout nesting, day assignment).
- [MVP] Daily clarity UI is calendar-first.
- [MVP] Data trust view for athletes is simple: show accessible programs and each program owner.
- [MVP] Logging requires completion only; detailed per-set actuals remain optional.
- [MVP] If multiple workouts are on the same day, collapse into a day summary with expand-to-view details.
- [MVP] Progress starts with load-based dashboard: weekly total load + type breakdown + hard/medium/easy distribution.
- [MVP] Direct owner messaging exists at program scope and is not tied to workout-instance comments.
- [Post-MVP] Unread indicators exist at both levels: per workout instance and program-level summary.
- [Post-MVP] Rescheduling is athlete self-reschedule.
- [Post-MVP] Reliability priority is offline draft logging.
- [Post-MVP] Safety priority is pain/discomfort tracking.

## Common Workflows

### Program Owner Workflows

- [MVP] Create program and publish first version:
	1. Owner creates a Workout Program and sets basic metadata.
	2. Owner creates Exercise Templates (video + instructions).
	3. Owner builds Workout Templates (including one-level child workout nesting in UI).
	4. Owner assigns workout type tags and prescription defaults.
	5. Owner arranges Program-to-Workout order and publishes.

- [MVP] Copy an existing owner program:
	1. Owner selects one of their existing programs.
	2. System creates a copied draft with duplicated structure/templates.
	3. Owner renames/edits and republishes as a separate program.

- [MVP] Enroll athletes and assign schedule:
	1. Owner finds athlete by exact username (opt-in discoverability only).
	2. Owner grants Program Enrollment.
	3. System records `addedAt` timestamp for that athlete-program enrollment.
	4. Owner assigns workouts to calendar dates (date-only in MVP).
	5. System creates Workout Instances at schedule time.

- [MVP] Monitor adherence and load:
	1. Owner opens program roster/adherence view.
	2. Owner reviews completion, missed sessions, and streak signals.
	3. Owner opens load dashboard (weekly total, type breakdown, hard/medium/easy).
	4. Owner drills into athlete-level recent workout instances when needed.

- [MVP] Respond to athlete direct messages:
	1. Athlete sends a direct message at program scope (not tied to a workout instance).
	2. Owner receives unread signal in the program inbox.
	3. Owner replies in the same direct thread.
	4. Thread remains separate from workout-instance comments.

- [MVP] Update a workout template after athletes are scheduled:
	1. Owner edits a Workout Template.
	2. Owner sees change-impact preview for uncompleted scheduled items.
	3. Owner publishes updated template version.
	4. System auto-updates uncompleted scheduled items to latest template version.

- [Post-MVP] Handle athlete reschedule and training conflicts:
	1. Athlete requests or performs self-reschedule.
	2. System validates conflict rules and date constraints.
	3. Owner reviews exceptions when required.
	4. Schedule is updated and notifications are sent.

- [Post-MVP] Safety intervention workflow:
	1. Athlete flags pain/discomfort or exercise issue.
	2. Owner receives alert and opens flagged workout instance.
	3. Owner applies contraindication-aware substitutions and safety notes.
	4. Updated prescription is tracked in audit history.

### Athlete Workflows

- [MVP] View daily plan:
	1. Athlete opens Today/calendar-first view.
	2. Athlete sees due, upcoming, and missed workouts with status.
	3. Athlete expands day summary when multiple workouts are scheduled.

- [MVP] Create a personal program:
	1. Athlete creates a personal workout program for self-use.
	2. Athlete adds workouts/exercises, uses workout nesting, and assigns sessions to calendar days.
	3. Athlete can copy the personal program to create a new variant.
	4. System enforces non-assignable scope (cannot enroll or assign other users).

- [MVP] Complete workout and log training load inputs:
	1. Athlete opens scheduled Workout Instance.
	2. Athlete records completion plus optional actual sets/reps/weight adjustments.
	3. Athlete logs required RPE (1–10) and duration.
	4. System computes and stores load points (versioned formula) on save.

- [MVP] Review progress and access visibility:
	1. Athlete opens progress dashboard.
	2. Athlete reviews weekly load, type distribution, and hard/medium/easy mix.
	3. Athlete opens data trust view to see accessible programs and program owners.

- [MVP] Send a direct message to program owner:
	1. Athlete opens the program-level direct message thread.
	2. Athlete sends a message unrelated to a specific workout.
	3. Owner can reply in the same thread.

- [MVP] Participate in private workout comments:
	1. Athlete opens a workout instance comment thread.
	2. Athlete and owner exchange private comments tied to that workout.
	3. Visibility remains limited to the assigned athlete and program owner.

- [Post-MVP] Continue workout logging while offline:
	1. Athlete logs workout data without network.
	2. App stores draft locally.
	3. App syncs on reconnect and resolves conflicts.

- [Post-MVP] Participate in program forum threads:
	1. Athlete posts in program-level forum threads/replies.
	2. System sends reply notifications and enforces per-program visibility.
	3. Athlete can include forum content in community data export.

## Expansion Concepts (Post-MVP)

- Program Marketplace: discovery-first launch (browse free/paid programs), with commerce flows deferred.
- Marketplace access lifecycle: support program durations, consent/waiver status tracking, automatic removal at end-of-duration, and pre-removal notifications.
- Group Plans: group progress model where members can see each others' completion status and group comments visible to others in the same group.

## Next Draft (Optional)

- Draft a concrete v1 data schema and API contract next (collections/tables, permissions, and exact screen list).
