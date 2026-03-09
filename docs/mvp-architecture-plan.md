# MVP Architecture & Delivery Plan

## Core Architecture to Define First

### Roles
- Account (base identity)
- Program Owner (per-program role)
- Athlete (per-program role)
- Optional Admin

### Main Entities
- Workout Program
- Exercise Template (reusable exercise definition with video + instructions)
- Workout Template (reusable workout definition; may contain child Workout Templates for nesting, e.g. a "Warmup" sub-workout inside a "Full Session")
- Program-to-Workout Mapping (ordered list)
- Workout-to-Exercise Mapping (ordered list + prescription fields such as sets/reps/weight)
- Workout-to-Workout Mapping (ordered list; allows a Workout Template to include child Workout Templates)
- Program Enrollment (manual access grant)
- Program Schedule (assignment of workouts to calendar dates)
- Workout Type (classification tag: e.g. limit, power, endurance for climbing; lower, upper, full_body for strength)
- Workout Instance (user completion record; includes RPE, duration, and optional workout-type override)
- Workout Instance Comments (owner + user replies)
- Program Forum (threads + replies)

## Auth / SSO Strategy

- Implement Google Sign-In now (Android).
- Add Apple Sign-In support in the backend model from day one (even if hidden on Android UI).
- On iOS launch, enable Apple Sign-In in the UI immediately to satisfy platform expectations.

## Build Order (MVP)

1. Phase 1: Auth + profiles + role model
2. Phase 2: Program creation + workout builder (including workout-type tags) + manual user assignment
3. Phase 3: Workout completion flow (RPE + duration + workout-type logging)
4. Phase 4: Load model dashboard (weekly total load, type breakdown, hard/medium/easy distribution)
5. Phase 5: Notifications (new assignment)

## Build Order (Post-MVP)

6. Phase 6: Workout-instance comment threads (private owner↔athlete) + program forum
7. Phase 7: Extended notifications (comment reply, forum reply)

## Important Design Decisions Now (to Avoid Rewrites)

- Keep `Workout Template` separate from `Workout Instance`.
- Allow the same person to be both a program owner and an athlete (role is contextual per program).
- Use role-based access checks on every read/write.
- Enforce per-program access control lists (ACL) so ownership and membership are scoped at the program level.
- Support owner-assigned access by username lookup, with the owner only seeing usernames during assignment.
- Version workout templates so old assigned programs remain stable.
- Allow owners to define exercises (video + instructions) and assemble them into workout programs with program/workout-level prescriptions.
- Add audit fields (`createdBy`, `assignedBy`, timestamps) everywhere.
- Support Workout Template nesting: the data model allows infinite depth (self-referential parent); the MVP UI supports one level of nesting (parent → children).

## Intensity & Load Model

### Workout Type Taxonomy

Workout type classifies what a session trains. The coach sets a default type on the Workout Template; the athlete can override it when logging their instance.

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

### Dashboard Widgets (Phase 4)

1. **Weekly Total Load** — sum of LoadPoints for the current week, with change vs prior week.
2. **Type Breakdown** — pie/bar chart by workout type.
3. **Hard / Medium / Easy** — session count by LoadPoints bucket (easy ≤ 6, medium 7–12, hard ≥ 13).

### Load Model Decisions (Locked)

- Store load model version alongside computed values so historical data stays stable if the formula changes.
- Compute load points on save (server-side) and store as a materialized field for fast dashboard queries.

## Decision Log (Locked for MVP)

- Create workout instances at schedule time.
- Use date-only assignment in MVP (no recurrence yet).
- Use athlete local timezone for day boundaries and due-date behavior.
- Allow athletes to adjust sets/reps/weight per workout instance.
- Athletes log RPE (1–10) and duration per workout instance; these are required for load computation.
- Coach sets a default workout type on the Workout Template; athletes may override it when completing an instance.
- Load points are computed server-side on save using a versioned formula (TypeWeight × Effort × DurationModifier).
- Keep workout-instance comments private to assigned athlete and program owner; allow edits.
- Auto-update all uncompleted scheduled items to the latest workout template version.
- Mark overdue workouts as missed and keep the original scheduled date.
- Allow assignment by exact username only, with user-controlled opt-in discoverability.

## Athlete Experience Requirements

- [MVP] Daily clarity: a clear "Today" view showing due, upcoming, and missed workouts.
- [MVP] Flexible logging: capture actual sets/reps/weight, RPE (1–10), duration, and optional workout-type override plus athlete notes per workout instance.
- [MVP] Progress visibility: load trends (weekly total, type distribution, hard/medium/easy), consistency streaks, and personal bests.
- [Post-MVP] Communication clarity: private owner↔athlete comments with unread indicators.
- [MVP] Calendar usability: visible schedule by day and clear status (scheduled, completed, missed).
- [MVP] Data trust: athletes can see who can access their workout data and comment threads.
- [Post-MVP] Scheduling flexibility: athlete reschedule request flow and conflict handling.
- [Post-MVP] Reliability: offline draft logging and media-performance optimizations.
- [Post-MVP] Safety support: contraindication notes, substitutions, and report-exercise-issue flow.

### Athlete Decision Log (Locked)

- [MVP] Daily clarity UI is calendar-first.
- [MVP] Logging requires completion only; detailed per-set actuals remain optional.
- [MVP] If multiple workouts are on the same day, collapse into a day summary with expand-to-view details.
- [MVP] Data trust view for athletes is simple: show accessible programs and each program owner.
- [MVP] Progress starts with load-based dashboard: weekly total load + type breakdown + hard/medium/easy distribution.
- [Post-MVP] Unread indicators exist at both levels: per workout instance and program-level summary.
- [Post-MVP] Rescheduling is athlete self-reschedule.
- [Post-MVP] Reliability priority is offline draft logging.
- [Post-MVP] Safety priority is pain/discomfort tracking.

## Expansion Concepts (Post-MVP)

- Program Marketplace: discovery-first launch (browse free/paid programs), with commerce flows deferred.
- Group Plans: group progress model where members can see each others' completion status and shared comments.

## Next Draft (Optional)

- Draft a concrete v1 data schema and API contract next (collections/tables, permissions, and exact screen list).
