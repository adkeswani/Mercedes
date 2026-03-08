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
- Workout Template (reusable workout definition)
- Program-to-Workout Mapping (ordered list)
- Workout-to-Exercise Mapping (ordered list + prescription fields such as sets/reps/weight)
- Program Enrollment (manual access grant)
- Program Schedule (assignment of workouts to calendar dates)
- Workout Instance (user completion record)
- Workout Instance Comments (owner + user replies)
- Program Forum (threads + replies)

## Auth / SSO Strategy

- Implement Google Sign-In now (Android).
- Add Apple Sign-In support in the backend model from day one (even if hidden on Android UI).
- On iOS launch, enable Apple Sign-In in the UI immediately to satisfy platform expectations.

## Build Order (MVP)

1. Phase 1: Auth + profiles + role model
2. Phase 2: Program creation + workout builder + manual user assignment
3. Phase 3: Workout completion flow + private per-instance comment thread
4. Phase 4: Program forum (public to program members)
5. Phase 5: Notifications (new assignment, comment reply, forum reply)

## Important Design Decisions Now (to Avoid Rewrites)

- Keep `Workout Template` separate from `Workout Instance`.
- Allow the same person to be both a program owner and an athlete (role is contextual per program).
- Use role-based access checks on every read/write.
- Enforce per-program access control lists (ACL) so ownership and membership are scoped at the program level.
- Support owner-assigned access by username lookup, with the owner only seeing usernames during assignment.
- Version workout templates so old assigned programs remain stable.
- Allow owners to define exercises (video + instructions) and assemble them into workout programs with program/workout-level prescriptions.
- Add audit fields (`createdBy`, `assignedBy`, timestamps) everywhere.

## Decision Log (Locked for MVP)

- Create workout instances at schedule time.
- Use date-only assignment in MVP (no recurrence yet).
- Use athlete local timezone for day boundaries and due-date behavior.
- Allow athletes to adjust sets/reps/weight per workout instance.
- Keep workout-instance comments private to assigned athlete and program owner; allow edits.
- Auto-update all uncompleted scheduled items to the latest workout template version.
- Mark overdue workouts as missed and keep the original scheduled date.
- Allow assignment by exact username only, with user-controlled opt-in discoverability.

## Athlete Experience Requirements

- [MVP] Daily clarity: a clear "Today" view showing due, upcoming, and missed workouts.
- [MVP] Flexible logging: capture actual sets/reps/weight plus optional athlete notes per workout instance.
- [MVP] Communication clarity: private owner↔athlete comments with unread indicators.
- [MVP] Calendar usability: visible schedule by day and clear status (scheduled, completed, missed).
- [MVP] Data trust: athletes can see who can access their workout data and comment threads.
- [Post-MVP] Progress visibility: trends for consistency, volume, and personal bests.
- [Post-MVP] Scheduling flexibility: athlete reschedule request flow and conflict handling.
- [Post-MVP] Reliability: offline draft logging and media-performance optimizations.
- [Post-MVP] Safety support: contraindication notes, substitutions, and report-exercise-issue flow.

### Athlete Decision Log (Locked)

- [MVP] Daily clarity UI is calendar-first.
- [MVP] Logging requires completion only; detailed per-set actuals remain optional.
- [MVP] Unread indicators exist at both levels: per workout instance and program-level summary.
- [MVP] If multiple workouts are on the same day, collapse into a day summary with expand-to-view details.
- [MVP] Data trust view for athletes is simple: show accessible programs and each program owner.
- [Post-MVP] Progress starts with a balanced set: basic consistency + basic volume trend.
- [Post-MVP] Rescheduling is athlete self-reschedule.
- [Post-MVP] Reliability priority is offline draft logging.
- [Post-MVP] Safety priority is pain/discomfort tracking.

## Expansion Concepts (Post-MVP)

- Program Marketplace: discovery-first launch (browse free/paid programs), with commerce flows deferred.
- Group Plans: group progress model where members can see each others' completion status and shared comments.

## Next Draft (Optional)

- Draft a concrete v1 data schema and API contract next (collections/tables, permissions, and exact screen list).
