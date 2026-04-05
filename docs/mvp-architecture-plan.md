# MVP Architecture & Delivery Plan (v1.1)

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
- Workout-to-Exercise Mapping (ordered list + prescription fields such as sets/reps/weight/time; supports rep-based, time-based, and AMRAP exercise modes)
- Workout-to-Workout Mapping (ordered list; allows a Workout Template to include child Workout Templates)
- Program Enrollment (manual access grant; includes `addedAt` and nullable `removedAt` timestamps)
- Program Schedule (assignment of workouts to calendar dates; supports one-off and bounded recurring schedules with required end date)
- Workout Type (classification tag: e.g. limit, power, endurance for climbing; lower, upper, full_body for strength)
- Workout Instance (user completion record; includes RPE, duration, and per-exercise actuals with timer data)
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
5. [MVP] Community features (core): direct athlete↔owner messaging and private workout comments, with support for external photo links and YouTube links (plus in-app link preview when available).
6. [Post-MVP] Community features (forum): program-level forum with reply notifications and athlete download/export of community conversation data.
7. [Post-MVP] Marketplace and access lifecycle: program discovery, durations, consent/waiver tracking, expiry notifications, automatic enrollment removal, and paid Program Owner entitlement for assignable-program creation.
8. [Post-MVP] Group workouts/plans: shared group progress, completion visibility, and group comments visible to members of the same group.

### Exit Criteria by Area

1. Foundation planning is complete when auth, roles, ACL scoping, enrollment lifecycle fields (`addedAt`/`removedAt`), template versioning, and audit-field requirements are documented as locked constraints for implementation.
2. Workout plan creation is complete when owners can create/edit/publish versioned programs, copy their own programs, build reusable workouts/exercises, assign workout-type tags without data-model rewrites, and athletes can create personal programs with equivalent builder capabilities (copy, workout nesting, day assignment) that remain non-assignable.
3. Auth + athlete assignment is complete when sign-in works on target platforms, role-scoped ACL checks are enforced, athlete enrollment writes `addedAt`, and date-based scheduling creates workout instances reliably.
4. Load/difficulty model is complete when required RPE + duration are captured on completion, load points are computed client-side with versioning and server-side audit capability, dashboard widgets return correct weekly/type/bucket summaries, and athletes can export/download their workout + load history.
5. Community features (core) are complete when direct athlete↔owner messaging and private workout comments are live with correct per-program visibility and access control, and users can post external photo/YouTube links with in-app preview support where metadata is available.
6. Community features (forum) are complete when program-level forum threads/replies and reply notifications are live with correct per-program visibility, and athletes can export/download their community conversation data.
7. Marketplace and access lifecycle is complete when program discovery is usable, duration-based access rules are enforced, consent/waiver status is tracked, pre-expiry notifications are sent, removals write `removedAt`, and paid Program Owner entitlement gates assignable-program creation.
8. Group workouts/plans is complete when owners can run shared group plans, members can see group completion status appropriately, and group comments are visible to other members of the same group with role/privacy boundaries enforced.

## Important Design Decisions Now (to Avoid Rewrites)

- Keep `Workout Template` separate from `Workout Instance`.
- Allow the same person to be both a program owner and an athlete (role is contextual per program).
- Use role-based access checks on every read/write.
- Enforce per-program access control lists (ACL) so ownership and membership are scoped at the program level.
- Support owner-assigned access by username lookup, with the owner only seeing usernames during assignment.
- Version workout templates so old assigned programs remain stable.
- Version programs at the program level (workout list, order) so structural changes don't silently alter enrolled athletes' schedules.
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

- Entitlement enforcement: assignable-program creation/publish actions require active Program Owner entitlement at both create and publish time (Post-MVP monetization scope).

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
- Load computation uses a pluggable strategy pattern (`LoadStrategy` interface). The default v1 formula is `DefaultLoadStrategy`; alternative formulas can be added without modifying existing code.
- Program owners can override individual type weights per program (`typeWeightOverrides`) without creating a new strategy. Overrides are merged over the strategy defaults at computation time.
- Program owners can manually override the computed load points for any workout instance (`loadPointsOverride`). The computed value is preserved so the override can be removed later.

## Decision Log

- Create workout instances at schedule time.
- Use date-only assignment in MVP (no recurrence yet).
- Recurring schedules require an end date; all instances are materialized upfront via batch write (no rolling/infinite recurrence).
- Use athlete local timezone for day boundaries and due-date behavior.
- Allow athletes to adjust sets/reps/weight per workout instance.
- Athletes log RPE (1–10) and duration per workout instance; these are required for load computation.
- Coach sets the workout type on the Workout Template; athletes cannot override workout type when completing an instance.
- Program owners can copy their own programs; copied programs inherit structure and templates as a new editable draft.
- Athletes may create personal programs for self-use only; athlete-created programs cannot be assigned to other users.
- Athlete personal programs support the same builder actions as owner programs (copy, workout nesting, day assignment) but remain self-use and non-assignable.
- Load points are computed client-side on completion using a versioned, pluggable strategy (default: TypeWeight × Effort × DurationModifier). Source fields are always stored, so values can be batch-recomputed if needed.
- Program owners may set per-program type weight overrides to customize load computation for their coaching style.
- Program owners and athletes may manually override computed load points on any workout instance; the computed value is preserved alongside the override.
- Support a direct athlete↔program-owner message thread at program scope (outside workout instances), reusing comment/thread primitives.
- Keep workout-instance comments private to assigned athlete and program owner; allow edits.
- Support comments at three scopes: program-level, workout-level, and exercise-level, using a single unified comments model with optional scope fields.
- Copying a program creates a deep copy of the program document but uses shallow references to existing workout template versions and exercise templates. The copy is fully independent.
- In direct messages and workout comments, support external media links (photo URLs + YouTube URLs) and show in-app link previews when possible.
- Do not store uploaded photo/video binaries in app-controlled storage for MVP; use external links to reduce storage and bandwidth cost.
- Auto-update all uncompleted scheduled items to the latest workout template version.
- Mark overdue workouts as missed and keep the original scheduled date. Athletes can recover missed workouts by completing them later (missed → completed transition).
- Allow assignment by exact username only, with user-controlled opt-in discoverability.
- Persist program enrollment lifecycle timestamps (`addedAt` on enrollment creation, `removedAt` on access removal).
- User account deletion triggers a cascading cleanup function across all related collections; cleanup failures are logged and surfaced to admin for manual resolution.
- Programs are versioned at the program level (structure/workout list/order). Each publish creates an immutable snapshot. Enrollments reference the program version assigned.
- Athletes may complete a workout after its scheduled date (late completion); the instance retains the original `scheduledDate` and records the actual `completedAt` timestamp.
- Exercises support three modes: rep-based (`reps`), time-based (`time`), and as-many-reps-as-possible (`amrap`). The mode is set on the exercise prescription in the workout template.
- An integrated in-app timer tracks rest intervals between sets and work duration for time-based/AMRAP exercises. Actual rest and work times are recorded per exercise in the workout instance.
- Total workout duration is tracked automatically from "Start Workout" to "Finish Workout" and written to the workout instance.
- The app tracks custom analytics events for major operations (logins, completions, messages, enrollments, feedback) via Firebase Analytics.
- In-app feedback (bug reports, feature requests, general feedback) is collected via a feedback form and stored for admin review.

## Athlete Experience Requirements

- [MVP] Personal planning: athletes can create and manage personal programs that are visible only to themselves and cannot be assigned to others.
- [MVP] Personal builder parity: athlete personal programs support copy, workout nesting, and day assignment like owner-created programs.
- [MVP] Daily clarity: a clear "Today" view showing due, upcoming, and missed workouts.
- [MVP] Calendar usability: visible schedule by day and clear status (scheduled, completed, missed).
- [MVP] Data trust: athletes can see who can access their workout data and comment threads.
- [MVP] Flexible logging: capture actual sets/reps/weight, RPE (1–10), duration, and athlete notes per workout instance.
- [MVP] Integrated timer: in-app rest timer between sets and work timer for time-based exercises, with audio/haptic alerts and auto-advance.
- [MVP] Late completion: athletes can complete a workout after the scheduled date as long as it has not been marked missed.
- [MVP] Progress visibility: load trends (weekly total, type distribution, hard/medium/easy), consistency streaks, and personal bests.
- [MVP] Data portability (training): athletes can download/export their workout history and load metrics.
- [MVP] Communication clarity: direct message thread with program owner is available outside workouts.
- [MVP] Communication clarity: private owner↔athlete workout-instance comments are available.
- [MVP] Media in comments/messages: direct messages and workout comments support photo URL links and YouTube links with in-app preview when available, without app-hosted media uploads.
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
- [MVP] Dashboard views: all-programs overview, per-program roster and aggregate metrics, and per-athlete drill-down (see dashboard detail below).
- [Post-MVP] Safety controls: contraindication-aware substitutions, required warmup/cooldown rules, and exercise issue escalation.

### Program Owner Dashboard Views (MVP)

**All-Programs Overview:**
- Summary cards per program: active athlete count, completion rate this week, unread messages.
- Sorted by programs needing attention (lowest adherence or unread messages first).

**Per-Program View:**
- Roster list with per-athlete: last workout date, weekly completion %, streak status, unread message indicator.
- Aggregate charts: program-wide completion rate trend, load distribution, workout type breakdown.
- Quick action: message athlete, view athlete detail, bulk-assign schedule.

**Per-Athlete View (drill-down):**
- Athlete's schedule calendar with status coloring (scheduled/completed/missed).
- Recent workout instances with RPE, duration, load points, and athlete notes.
- Load trend chart (weekly totals, type breakdown, hard/medium/easy distribution).
- Direct message thread with that athlete.
- Comment history across workout instances.

### Athlete Decision Log

- [MVP] Personal programs are self-use only and non-assignable, with builder parity (copy, workout nesting, day assignment).
- [MVP] Daily clarity UI is calendar-first.
- [MVP] Data trust view for athletes is simple: show accessible programs and each program owner.
- [MVP] Logging requires completion only; detailed per-set actuals remain optional.
- [MVP] If multiple workouts are on the same day, collapse into a day summary with expand-to-view details.
- [MVP] Progress starts with load-based dashboard: weekly total load + type breakdown + hard/medium/easy distribution.
- [MVP] Direct owner messaging exists at program scope and is not tied to workout-instance comments.
- [MVP] Comment/message media uses external links only (photo URL and YouTube URL) to avoid MVP photo/video storage costs.
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
	3. Owner chooses upgrade scope: "Update all scheduled" (default) or "New only" (existing stay on current version).
	4. Owner publishes updated template version.
	5. System updates applicable scheduled items based on owner's choice.

- [MVP] Update program structure after athletes are enrolled:
	1. Owner adds, removes, or reorders workouts in a program.
	2. System shows impact preview (how many enrollments reference the current version).
	3. Owner publishes new program version.
	4. System snapshots the new structure; new schedule assignments use the new version.

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
	4. App computes and stores load points (versioned formula) on completion.

- [MVP] Use recurring schedule:
	1. Owner assigns a workout with recurring pattern (e.g., Mon/Wed/Fri) and an end date.
	2. System creates all workout instances upfront for the entire recurrence window.
	3. Athlete sees all scheduled dates in calendar view.
	4. Owner can cancel remaining, extend, or edit individual instances.

- [MVP] Review progress and access visibility:
	1. Athlete opens progress dashboard.
	2. Athlete reviews weekly load, type distribution, and hard/medium/easy mix.
	3. Athlete opens data trust view to see accessible programs and program owners.

- [MVP] Send a direct message to program owner:
	1. Athlete opens the program-level direct message thread.
	2. Athlete sends a message unrelated to a specific workout (text and optional external photo/YouTube links).
	3. Owner can reply in the same thread.

- [MVP] Participate in private workout comments:
	1. Athlete opens a workout instance comment thread.
	2. Athlete and owner exchange private comments tied to that workout, including optional external photo/YouTube links.
	3. Visibility remains limited to the assigned athlete and program owner.

- [Post-MVP] Continue workout logging while offline:
	1. Athlete logs workout data without network.
	2. App stores draft locally.
	3. App syncs on reconnect and resolves conflicts.

- [Post-MVP] Participate in program forum threads:
	1. Athlete posts in program-level forum threads/replies.
	2. System sends reply notifications and enforces per-program visibility.
	3. Athlete can include forum content in community data export.


## Athlete Goals & To-Do List (MVP Phase)

### Overview

Athletes can create, view, and manage a personal list of goals or "to-dos" within the app. Each goal can have an optional due date. Goals are displayed in a simple checklist UI, allowing athletes to check off completed items. Goals with dates appear on the same calendar as scheduled workouts, providing a unified view of training and personal objectives.

### Key Features

- **Create/Edit/Delete Goals:** Athletes can add new goals, edit existing ones, and remove goals from their list.
- **Completion Tracking:** Goals can be checked off when completed. Completed goals remain visible (with a checked state) until deleted.
- **Due Dates & Calendar Integration:** Goals can have an optional due date. Dated goals are shown on the athlete's calendar alongside workouts, with distinct visual markers.
- **Simple UI:** The to-do/goals screen is accessible from the main navigation or dashboard, with a clear add/check-off interaction.
- **Personal Scope:** Goals are private to the athlete and not visible to program owners or other users.

### Data Model (Draft)

```
goals/{goalId}
	athleteId: string (userId)
	title: string
	notes: string?
	dueDate: string? (ISO 8601 date)
	completed: bool (default false)
	completedAt: timestamp?
	createdAt: timestamp
	updatedAt: timestamp
```

### Calendar Integration

- The calendar view aggregates both scheduled workouts and goals with due dates.
- Tapping a date shows both workouts and any goals due that day.
- Overdue goals are visually indicated until checked off or deleted.

### Placement

This feature is included in the MVP phase, as it supports athlete engagement and self-management. It is implemented as a standalone screen and calendar integration, with no impact on program owner workflows or permissions.

---

## Expansion Concepts (Post-MVP)

- Program Marketplace: discovery-first launch (browse free/paid programs), with commerce flows deferred.
- Marketplace access lifecycle: support program durations, consent/waiver status tracking, automatic removal at end-of-duration, and pre-removal notifications.
- Program Owner monetization: paid owner tier unlocks creation of assignable programs, while athlete personal programs remain self-use and non-assignable.
- Group Plans: group progress model where members can see each others' completion status and group comments visible to others in the same group.

## Next Draft (Optional)

- Draft a concrete v1 data schema and API contract next (collections/tables, permissions, and exact screen list).
