# Technical Design — Locked Constraints (v0.4 DRAFT)

> **Status:** DRAFT — every section marked 🔒 is a locked decision.
> Sections marked ❓ need your input before they can be locked.
>
> This document satisfies Roadmap Step 1 ("Foundation planning") exit criteria:
> auth model, role/ACL boundaries, enrollment lifecycle, versioning/audit
> requirements documented as locked constraints for implementation.

---

## 1. Backend Stack 🔒

| Layer | Choice | Why |
|---|---|---|
| **Auth** | Firebase Authentication (Google Sign-In now; Apple Sign-In wired in backend, enabled on iOS launch) | Already in tooling-config (`firebase-tools`, `flutterfire_cli`). Supports multi-provider linking. |
| **Database** | Cloud Firestore | Real-time sync for comments/messages, offline support for mobile, security rules for ACL. |
| **Server-side compute** | Cloud Functions for Firebase (2nd gen, Dart or TypeScript) | Needed for: load-point computation on save, enrollment lifecycle writes, scheduled missed-workout marking, export generation. |
| **Hosting / CDN** | Firebase Hosting (web dashboard if needed post-MVP) | Bundled, zero-config. |
| **Storage** | None for MVP (external media links only per architecture plan) | Revisit post-MVP if user-uploaded media is needed. |

### Cloud Functions language: TypeScript 🔒

Cloud Functions are written in **TypeScript (Node.js)**. The Firebase Functions ecosystem, documentation, and community examples are overwhelmingly TypeScript. The ~9 MVP functions are short trigger handlers that don't benefit from Dart code sharing with Flutter.

---

## 2. Data Model Schema 🔒

All collections live at the Firestore root unless noted. Sub-collections are indented.

### 2.1 Users & Roles

```
users/{userId}
  uid: string (Firebase Auth UID)
  displayName: string
  username: string (unique — enforce via helper collection)
  email: string
  photoUrl: string?
  discoverable: bool (opt-in for username lookup)
  createdAt: timestamp
  updatedAt: timestamp

usernames/{username}           # uniqueness helper
  uid: string
```

**Roles are not stored on the user document.** A user's role is contextual per program — determined by whether they are the `ownerId` of a program or appear in its enrollments. The same person can be an owner of one program and an athlete in another. Only owners of `type: "assignable"` programs can enroll/assign other users. This is enforced by security rules (`isProgramOwner()`) and the `programs.type` field — no separate "role" field is needed.

### 2.2 Exercise Templates

```
exerciseTemplates/{exerciseId}
  name: string
  description: string
  videoUrl: string?
  instructions: string
  createdBy: string (userId)
  createdAt: timestamp
  updatedAt: timestamp
```

### 2.3 Workout Templates (versioned)

```
workoutTemplates/{workoutTemplateId}
  name: string
  workoutType: string (enum — see Workout Type Taxonomy in architecture plan)
  currentVersion: int
  createdBy: string (userId)
  createdAt: timestamp
  updatedAt: timestamp

  workoutTemplateVersions/{versionNumber}   # sub-collection
    versionNumber: int
    publishedAt: timestamp
    exercises: [                             # ordered list (array)
      {
        exerciseId: string
        sortOrder: int
        prescription: {
          mode: string            # "reps" | "time" | "amrap"
          sets: int?
          reps: string?           # e.g. "8-12" (used when mode = "reps" or "amrap")
          durationSeconds: int?   # target time per set (used when mode = "time")
          weight: string?         # e.g. "70%" or "135 lb"
          restSeconds: int?       # rest between sets (drives in-app timer)
          notes: string?
        }
      }
    ]
    childWorkouts: [                         # ordered nested workout refs
      {
        workoutTemplateId: string
        versionNumber: int
        sortOrder: int
      }
    ]
```

**Versioning strategy:** immutable sub-collection snapshots. Each publish creates a new `workoutTemplateVersions/{n}` document. Old versions are never mutated. Workout instances and program mappings reference a specific `(workoutTemplateId, versionNumber)` pair.

### 2.4 Programs (versioned)

```
programs/{programId}
  name: string
  description: string?
  ownerId: string (userId)
  type: string ("assignable" | "personal")
  status: string ("draft" | "published" | "archived")
  currentVersion: int
  typeWeightOverrides: map?              # per-program load weight overrides (e.g. { "power": 3 })
  loadStrategyId: string?               # alternative load strategy (null = default_v1)
  createdBy: string (userId)
  createdAt: timestamp
  updatedAt: timestamp

  programVersions/{versionNumber}           # immutable structure snapshot
    versionNumber: int
    publishedAt: timestamp
    workouts: [
      {
        workoutTemplateId: string
        workoutTemplateVersion: int
        sortOrder: int
      }
    ]
    changeNote: string?                     # owner's description of what changed
```

There is no `programWorkouts` sub-collection. The owner edits workout list/order in a **local draft state** (Riverpod, not persisted to Firestore). On publish, the snapshot goes directly into `programVersions/{n}`. The latest published version is the source of truth for the current program structure.

**Program versioning strategy:** mirrors workout template versioning. Each publish snapshots the full workout list + order into `programVersions/{n}`. Enrollments and workout instances reference a `(programId, programVersion)` pair. This preserves the exact program structure each athlete was assigned, even if the owner later adds/removes/reorders workouts.

### 2.5 Enrollment

```
enrollments/{enrollmentId}
  programId: string
  athleteId: string (userId)
  addedAt: timestamp
  addedBy: string (userId)
  removedAt: timestamp?
  removedBy: string?
  status: string ("active" | "removed")
```

A compound index on `(programId, athleteId, status)` supports fast ACL lookups.

### 2.6 Workout Instances

```
workoutInstances/{instanceId}
  programId: string
  athleteId: string (userId)
  workoutTemplateId: string
  workoutTemplateVersion: int
  scheduledDate: string (ISO 8601 date, e.g. "2026-04-15")
  assignedBy: string (userId)
  assignedAt: timestamp
  status: string ("scheduled" | "completed" | "missed")
  completedAt: timestamp?                    # may be after scheduledDate (late completion allowed)
  missedAt: timestamp?                       # set by cron; cleared if athlete later completes
  rpe: int? (1–10, required on completion)
  durationMinutes: int? (required on completion)
  loadPoints: number? (computed client-side)
  loadPointsOverride: number?            # manual override by owner or athlete (takes precedence)
  loadPointsOverriddenBy: string?        # userId of who set the override
  loadPointsOverriddenAt: timestamp?     # when the override was set
  loadModelVersion: int (e.g. 1)
  loadStrategyId: string?                # strategy used for computation (null = default_v1)
  workoutType: string (copied from template at creation)
  recurrence: {                              # null for one-off assignments
    pattern: string                          # "weekly" | "biweekly" | "custom"
    daysOfWeek: [int]?                       # 1=Mon..7=Sun (for weekly/biweekly)
    intervalDays: int?                       # for custom patterns
    endDate: string (ISO 8601 date)          # REQUIRED — bounded recurrence
  }?
  isRecurrenceRoot: bool                     # true for the original instance in a recurrence
  recurrenceRootId: string?                  # points to the root instanceId for materialized siblings
  actuals: [
    {
      exerciseId: string
      mode: string               # "reps" | "time" | "amrap"
      sets: int?
      reps: string?
      durationSeconds: int?      # actual time per set (time-based exercises)
      weight: string?
      restSeconds: int?          # actual rest taken (tracked by timer)
      notes: string?
    }
  ]
  athleteNotes: string?
  createdAt: timestamp
  updatedAt: timestamp
```

### 2.7 Comments (unified) 🔒

A single collection handles all comment scopes: program-level, workout-level, and exercise-level. The scope is determined by which optional ID fields are populated.

```
comments/{commentId}
  programId: string                          # always set (for ACL)
  workoutInstanceId: string?                 # null → program-level comment
  exerciseId: string?                        # null → workout-level comment; set → exercise-level
  groupId: string?                           # null → private (athlete+owner); set → visible to group members (post-MVP)
  athleteId: string (userId)                 # the athlete this comment thread belongs to
  authorId: string (userId)                  # who wrote this comment
  body: string
  mediaLinks: [string]?                      # external URLs
  createdAt: timestamp
  editedAt: timestamp?
```

**Scope queries** (all use composite indexes, fast regardless of collection size):

| Scope | Query |
|---|---|
| Program-level (DM replacement) | `where programId == X AND athleteId == Y AND workoutInstanceId == null` |
| Workout-level | `where workoutInstanceId == X AND exerciseId == null` |
| Exercise-level | `where workoutInstanceId == X AND exerciseId == Y` |
| All comments for an athlete in a program | `where programId == X AND athleteId == Y` |
| Group comments (post-MVP) | `where workoutInstanceId == X AND groupId == G` |

**Visibility:**
- **MVP (private):** `groupId == null` — comments are visible only to the assigned athlete and the program owner. ACL enforced via `isProgramOwner(programId) || isSelfAthlete()`.
- **Post-MVP (group):** `groupId != null` — comments are visible to all members of the group and the program owner. ACL enforced via group membership check.

### 2.8 Direct Message Threads

```
directMessageThreads/{threadId}
  programId: string
  athleteId: string (userId)
  ownerId: string (userId)
  createdAt: timestamp

  messages/{messageId}                       # sub-collection
    senderId: string (userId)
    body: string
    mediaLinks: [string]?                    # external URLs
    createdAt: timestamp
    editedAt: timestamp?
```

Direct messages remain separate from the unified comments collection because they serve a different purpose (open-ended conversation vs. contextual feedback) and have different access patterns (threaded chat vs. scoped comment list).

### 2.9 Notifications

```
notifications/{notificationId}
  recipientId: string (userId)
  type: string ("comment" | "message" | "enrollment" | "workout_assigned" | "missed_workout" | "template_updated")
  title: string
  body: string?
  programId: string?
  workoutInstanceId: string?
  commentId: string?
  read: bool (default false)
  createdAt: timestamp
```

Notifications are written by Cloud Functions alongside the action that triggers them (e.g., `onTemplatePublished` writes a notification to affected athletes). The app queries `where recipientId == auth.uid AND read == false` for unread badges.

### 2.10 Audit Fields Convention 🔒

Every document includes at minimum: `createdAt`, `updatedAt`. Documents involving assignment/enrollment also include `createdBy`/`assignedBy`/`addedBy` as applicable (see individual schemas above).

---

## 3. ACL Enforcement 🔒

**Primary enforcement layer:** Firestore Security Rules with reusable helper functions.

**Principle:** default-deny. Every rule calls one of the named helpers below rather than inlining checks.

**Secondary enforcement (defense-in-depth):** Cloud Functions that write sensitive data (load points, enrollment lifecycle fields, missed-workout marking) validate the same conditions server-side.

### Reusable Security Rule Helpers

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // ── Helper functions (called by every collection's rules) ──

    function isSignedIn() {
      return request.auth != null;
    }

    function isProgramOwner(programId) {
      return isSignedIn()
             && get(/databases/$(database)/documents/programs/$(programId)).data.ownerId
                == request.auth.uid;
    }

    function isEnrolledActive(programId) {
      return isSignedIn()
             && exists(/databases/$(database)/documents/enrollments/$(programId + '_' + request.auth.uid))
             && get(/databases/$(database)/documents/enrollments/$(programId + '_' + request.auth.uid)).data.status
                == 'active';
    }

    function isAthleteOrOwner(programId) {
      return isProgramOwner(programId) || isEnrolledActive(programId);
    }

    function isSelf(userId) {
      return isSignedIn() && request.auth.uid == userId;
    }

    function isSelfAthlete() {
      return isSignedIn() && resource.data.athleteId == request.auth.uid;
    }

    // ── Collection rules (expand per-collection during implementation) ──

    match /programs/{programId} {
      allow read: if isSignedIn()
                    && (resource.data.ownerId == request.auth.uid
                        || resource.data.status == 'published'
                        || isEnrolledActive(programId));
      allow create: if isSelf(request.resource.data.ownerId);
      allow update, delete: if isProgramOwner(programId);
    }

    match /workoutInstances/{instanceId} {
      allow read: if isSelfAthlete()
                    || isProgramOwner(resource.data.programId);
      allow update: if isSelfAthlete();
    }

    match /directMessageThreads/{threadId} {
      allow read: if isSignedIn()
                    && (resource.data.athleteId == request.auth.uid
                        || resource.data.ownerId == request.auth.uid);
    }

    // ... additional collections follow the same pattern
  }
}
```

### Helper Summary

| Helper | Purpose | Used by |
|---|---|---|
| `isSignedIn()` | Base auth gate | All rules |
| `isProgramOwner(programId)` | Owner-only writes, roster management | programs, enrollment, workoutInstances, comments |
| `isEnrolledActive(programId)` | Athlete read access, completion writes | workoutInstances, messaging |
| `isAthleteOrOwner(programId)` | Shared read contexts | messaging threads, comments |
| `isSelf(userId)` | Profile edits, personal programs | users, programs (type=personal) |
| `isSelfAthlete()` | Workout completion, actuals logging | workoutInstances |

Full security rules will be developed collection-by-collection alongside feature implementation and tested with the Firebase Emulator Suite.

---

## 4. Template Versioning Strategy 🔒

| Principle | Detail |
|---|---|
| Immutable versions | Each publish creates a new `workoutTemplateVersions/{n}` sub-document. Published versions are never edited. |
| Pinned references | `programVersions` and `workoutInstances` store an explicit `(workoutTemplateId, versionNumber)` pair. |
| Auto-upgrade uncompleted | On template publish, queries all `workoutInstances` with `status == "scheduled"` referencing that template. The owner chooses the upgrade scope (see below). Completed/missed instances are never touched. |
| Owner preview & choice | Before publishing, the UI shows a "change-impact preview" listing how many scheduled instances exist. The owner selects: **"Update all scheduled"** (default — all existing scheduled instances move to the new version) or **"New only"** (existing scheduled instances keep their current version; only instances created after this publish use the new version). |
| Program-level versioning | Adding/removing/reordering workouts in a program creates a new `programVersions/{n}` snapshot. Enrollments reference the program version they were assigned. |

### Walkthrough: How Versioning Works End-to-End

**Setup:** Coach Alice creates workout template "Upper Pull Day" and publishes it as **v1**. She adds it to her program "8-Week Strength" at slot 3. She enrolls athletes Bob and Carol and assigns "Upper Pull Day" to April 10.

```
workoutTemplates/abc123
  currentVersion: 1

  workoutTemplateVersions/1          ← immutable snapshot
    exercises: [lat pulldown 3×10, barbell row 4×8, ...]
    publishedAt: 2026-04-01

programWorkouts/slot3
  workoutTemplateId: abc123
  workoutTemplateVersion: 1

workoutInstances/bob_apr10           workoutInstances/carol_apr10
  workoutTemplateId: abc123            workoutTemplateId: abc123
  workoutTemplateVersion: 1            workoutTemplateVersion: 1
  status: "scheduled"                  status: "scheduled"
```

**Day 5 — Bob completes the workout.** His instance moves to `status: "completed"`, `completedAt` is written, and the load function fires. His `workoutTemplateVersion` stays **1** forever.

**Day 7 — Alice edits the template.** She swaps barbell row for pendlay row and adds a face-pull exercise. She hits **Publish**. The app shows: *"1 scheduled instance will be updated to v2."* She confirms.

```
workoutTemplateVersions/2            ← new immutable snapshot
  exercises: [lat pulldown 3×10, pendlay row 4×8, face pull 3×15, ...]
  publishedAt: 2026-04-07

Cloud Function runs:
  • bob_apr10   → status: "completed" → SKIP (no change)
  • carol_apr10 → status: "scheduled" → UPDATE workoutTemplateVersion to 2
```

**Day 10 — Carol opens the app.** She sees the **v2** workout (with pendlay row). She completes it. Her instance now permanently records `workoutTemplateVersion: 2`.

**Result:** Bob's historical record reflects the v1 template he actually performed. Carol's reflects v2. Both are accurate. Neither was silently changed after completion.

**What if Alice publishes v3 later?** Same pattern — only `status: "scheduled"` instances are touched. Completed and missed instances are immutable historical records.

### Walkthrough: Program-Level Versioning

**Setup:** Coach Alice's program "8-Week Strength" has 5 workouts in its v1 structure: [Upper Pull, Lower Push, Full Body, Upper Push, Lower Pull]. She publishes this as **program v1** and enrolls Bob.

```
programs/prog789
  currentVersion: 1
  status: "published"

  programVersions/1
    workouts: [Upper Pull v1, Lower Push v1, Full Body v1, Upper Push v1, Lower Pull v1]
    publishedAt: 2026-04-01

enrollments/bob_prog789
  programVersion: 1
```

**Week 3 — Alice restructures the program.** She removes Full Body, adds a Mobility session, and reorders. She edits this in her local draft (Riverpod state, not yet in Firestore). She hits **Publish**.

```
programVersions/2
  workouts: [Upper Pull v1, Lower Push v1, Mobility v1, Upper Push v1, Lower Pull v1]
  publishedAt: 2026-04-15
  changeNote: "Replaced Full Body with Mobility; reordered"

programs/prog789
  currentVersion: 2
```

**What happens to Bob?** Alice chooses:
- **"Update all"** → Bob's enrollment moves to program v2. Future workout assignments use the new structure.
- **"New only"** → Bob stays on program v1 for existing scheduled instances. Only newly assigned workouts use v2.

**New enrollee Carol joins later.** She always gets the latest published version (v2).

### Deep Copy Behavior (Program & Workout Copy) 🔒

When an owner copies a program:

| What | Copy behavior |
|---|---|
| `programs/{id}` document | **Deep copy** — new document with new ID, `status: "draft"`, owner = copier |
| `programVersions` | **Not copied** — the new program starts fresh with no versions (draft state) |
| Workout list (from latest `programVersions/{n}`) | **Copied as draft structure** — workout references are cloned into the new program's local draft |
| `workoutTemplates` and `workoutTemplateVersions` | **Shallow reference** — the copy references the same immutable template versions, not duplicates. The copier can later edit and publish their own new versions. |
| `exerciseTemplates` | **Shallow reference** — same exercise template IDs are reused |
| `enrollments` | **Not copied** — the new program starts with no athletes |

This means copying is fast (no bulk document duplication) and the copy is fully independent — changes to the original don't affect the copy, and vice versa.

---

## 5. Flutter Project Structure & State Management 🔒

### State Management: Riverpod

Why: compile-safe, testable, no `BuildContext`-dependent lookups, strong community adoption for mid-to-large Flutter apps.

### Folder Structure (feature-first)

```
lib/
  main.dart
  app.dart                        # MaterialApp, router, theme
  firebase_options.dart            # generated by FlutterFire CLI
  core/
    constants/
    exceptions/
    extensions/
    routing/                       # GoRouter config
    theme/
    utils/
  features/
    auth/
      data/                        # repositories, data sources
      domain/                      # models, enums
      presentation/                # screens, widgets, controllers
    programs/
      data/
      domain/
      presentation/
    workouts/
      data/
      domain/
      presentation/
    schedule/
      data/
      domain/
      presentation/
    load/                          # load model, dashboard
      data/
      domain/
      presentation/
    messaging/
      data/
      domain/
      presentation/
    profile/
      data/
      domain/
      presentation/
  shared/
    widgets/                       # reusable UI components
    providers/                     # app-wide Riverpod providers
```

### Key Libraries (anticipated)

| Purpose | Package | License |
|---|---|---|
| State management | `flutter_riverpod` | MIT |
| Routing | `go_router` | BSD-3-Clause |
| Firebase core | `firebase_core` | BSD-3-Clause |
| Firebase auth | `firebase_auth` | BSD-3-Clause |
| Google sign-in | `google_sign_in` | BSD-3-Clause |
| Firestore | `cloud_firestore` | BSD-3-Clause |
| Cloud Functions client | `cloud_functions` | BSD-3-Clause |
| Functional helpers | `freezed`, `freezed_annotation`, `json_serializable` | MIT / BSD-3-Clause |
| URL preview | `any_link_preview` or similar | MIT |
| Analytics | `firebase_analytics` | BSD-3-Clause |
| Crash reporting | `firebase_crashlytics` | BSD-3-Clause |

> When these are added to `pubspec.yaml`, update `THIRD_PARTY_NOTICES.md` in the same commit per repo policy.

### License & Commercial Use Note

All anticipated dependencies use **MIT**, **BSD-3-Clause**, or **Apache-2.0** licenses — all explicitly permit commercial use, modification, and distribution. The only GPL-licensed tool is **Git** itself (GPL-2.0), which is used as an external development tool and does not affect the app's licensing. Firebase/Google Cloud services are governed by the Google Cloud Terms of Service, which permit commercial use.

---

## 6. Auth Flow (end-to-end) 🔒

```
┌──────────┐     ┌────────────────┐     ┌──────────────┐
│  App UI  │────▶│ google_sign_in │────▶│ Firebase Auth │
│ (Flutter)│     │   (SDK)        │     │  (backend)   │
└──────────┘     └────────────────┘     └──────┬───────┘
                                               │
                                  ID token + UID│
                                               ▼
                                     ┌──────────────┐
                                     │ Cloud Function│
                                     │ onCreate user │
                                     └──────┬───────┘
                                            │
                               creates user doc│
                                            ▼
                                     ┌──────────────┐
                                     │  Firestore   │
                                     │ users/{uid}  │
                                     └──────────────┘
```

1. User taps "Sign in with Google."
2. `google_sign_in` SDK opens consent UI → returns Google credential.
3. `firebase_auth` exchanges credential → Firebase Auth creates/finds user → returns `UserCredential`.
4. A `functions.auth.user().onCreate` Cloud Function fires, creating the `users/{uid}` document with initial fields.
5. App listens to `authStateChanges()` stream → on authenticated, reads the user document → navigates to home.

**Apple Sign-In:** Same flow but with `sign_in_with_apple` SDK. Backend user doc creation is identical. Hidden on Android UI for MVP; enabled on iOS.

---

## 7. Load Computation Contract 🔒

### Computation approach: client-side only

The load formula is computed **client-side** when the athlete completes a workout. This avoids a Cloud Function invocation on every completion, works offline, and reduces cost. The formula is deterministic and simple enough that client-side execution is reliable.

If incorrect values are ever discovered, they can be batch-recomputed from the stored source fields (`rpe`, `durationMinutes`, `workoutType`) using a one-off script.

### Formula (v1)

```
Input:  rpe (1–10), durationMinutes (int), workoutType (string)
Output: loadPoints (number), loadModelVersion (int = 1)

TypeWeights = { limit: 5, power: 4, power_endurance: 4, endurance: 2,
                skill: 2, cardio: 2, mobility: 1,
                lower: 4, legs: 4, upper: 3, full_body: 3,
                push: 3, pull: 3, core: 2, conditioning: 2 }

EffortMap(rpe) = rpe 1-2→1, 3-4→2, 5-6→3, 7-8→4, 9-10→5

DurationMod(min) = <30→0.75, 30-75→1.0, >75→1.25

loadPoints = TypeWeights[workoutType] × EffortMap(rpe) × DurationMod(durationMinutes)
```

The client writes `loadPoints` and `loadModelVersion` to the workout instance document on completion. `loadModelVersion` is stored alongside so historical values remain interpretable if the formula changes later.

### Why client-side?

- **Works offline** — no network needed to compute load on workout completion.
- **Zero cost** — no Cloud Function invocation per completion.
- **Instant** — no round-trip latency.
- **Low risk** — athletes have no incentive to tamper with personal training metrics. Source fields are always stored and values can be recomputed from them at any time.
- **Version-tracked** — `loadModelVersion` identifies which formula produced each value, so formula changes don't corrupt historical data.

### Extensibility 🔒

The load computation system supports three levels of customization:

**1. Pluggable strategies (`LoadStrategy` interface)**
New calculation formulas are added by implementing the `LoadStrategy` interface. Each strategy declares a `version` and `name`. The default formula is `DefaultLoadStrategy` (`default_v1`). Programs reference a strategy by name via `loadStrategyId`; when null, the default is used. Historical instances record which strategy produced their value via `loadStrategyId` + `loadModelVersion`.

**2. Per-program type weight overrides**
Program owners can customize individual type weights without creating a new strategy. The `programs.typeWeightOverrides` map (e.g. `{ "power": 3 }`) is merged over the strategy's defaults at computation time. This allows a climbing coach to value "power" sessions differently than a strength coach without altering the global formula. Override values must be positive integers; validation is enforced at the model layer.

**3. Manual load override**
Program owners and athletes can manually override the computed load points for any workout instance by setting `workoutInstances.loadPointsOverride`. When present, this value takes precedence over the computed `loadPoints` in all dashboard queries and aggregations. The computed value is preserved alongside the override so it can be restored if the override is removed.

---

## 8. In-App Timer & Time-Based Exercises 🔒

Exercises support three modes via the `prescription.mode` field:

| Mode | Description | Timer behavior |
|---|---|---|
| `reps` | Traditional rep-based (e.g. 3×10) | Rest timer starts automatically after athlete taps "Set done" |
| `time` | Time-based work (e.g. 45s hang) | Work timer counts down `durationSeconds`, then rest timer counts down `restSeconds` |
| `amrap` | As many reps as possible in a time window | Work timer counts down `durationSeconds`, athlete logs reps achieved |

### Timer Implementation

- **Local-only** — the timer runs on-device, not on the server. No network dependency during a workout.
- **Rest timer** — between sets, counts down `restSeconds` from the prescription. Audio/haptic alert on completion. Athlete can skip or extend.
- **Work timer** — for `time` and `amrap` modes, counts down `durationSeconds`. Audio/haptic alert on completion.
- **Auto-advance** — when rest expires, the UI advances to the next set. When all sets complete, advances to the next exercise.
- **Duration tracking** — total workout duration is tracked from "Start Workout" to "Finish Workout" and written to `workoutInstances.durationMinutes`.
- **Per-exercise actuals** — actual `restSeconds` and `durationSeconds` are recorded in the `actuals` array so the athlete (and coach) can see deviations from the prescription.

---

## 9. Data Evolution Strategy 🔒

Firestore is schemaless — adding new fields to documents is non-breaking by default. Old documents simply won't have the new field, and Dart model classes handle `null` with default values.

### Adding Fields

No migration needed. Add the field to the Dart model with a nullable type or a default. Old documents remain valid.

### Backfilling Existing Documents

When a new field must be populated on existing documents (e.g. adding a `workoutType` field to old instances), write a one-off Cloud Function or admin script that queries + batch-updates affected documents.

### Changing Computed Values (Load Model Example)

The `loadModelVersion` field on `workoutInstances` is the pattern for any computed value that might change:

1. Bump `loadModelVersion` in the new Cloud Function code.
2. New completions are computed with the new formula and tagged with the new version.
3. Historical documents retain the old `loadModelVersion` and old `loadPoints` — they remain accurate for the formula that produced them.
4. If you want to recompute historical data, run a backfill script that recalculates and updates `loadPoints` + `loadModelVersion`.

### Schema Version Registry

For tracking which model changes have been applied:

```
schemaVersions/{versionId}
  collection: string       # e.g. "workoutInstances"
  version: int             # sequential
  description: string      # e.g. "Added workoutType field"
  appliedAt: timestamp
  backfillStatus: string   # "pending" | "running" | "complete" | "not_needed"
```

This collection acts as a migration log. It's checked by admin tooling, not by the app at runtime.

---

## 10. Caching Strategy 🔒

| Layer | Mechanism | What it caches | Invalidation |
|---|---|---|---|
| **Firestore offline persistence** | Built-in (enabled by default on mobile) | All recently read documents | Automatic on reconnect; Firestore SDK reconciles local cache with server |
| **Riverpod in-memory cache** | `StateProvider` / `AsyncNotifierProvider` | User profile, current program, exercise templates, workout template for active session | Disposed when provider is no longer listened to; manually invalidated on write |
| **Workout session (in-progress)** | Local state held in a Riverpod provider | Timer state, current set/rep, partial actuals | Persisted to local storage on background/kill; restored on reopen |
| **Dashboard aggregates** | Riverpod + optional local storage | Weekly load totals, type breakdowns | Refreshed on pull-to-refresh or when a new workout instance is completed |
| **Exercise template library** | Riverpod with stale-while-revalidate | Full exercise list for the builder UI | Background refresh; re-fetch on builder screen open |

### Cache Design Principles

- **Firestore listeners (snapshots)** are the primary real-time sync mechanism for collections that change in response to other users (messages, comments, enrollment changes).
- **One-shot reads with Riverpod caching** for data that changes rarely (exercise templates, user profile, program metadata).
- **No custom SQLite or Hive cache** in MVP — Firestore offline persistence + Riverpod covers the use cases. Revisit if offline-first workout logging needs a local queue.

---

## 11. Observability & Analytics 🔒

### Error Tracking

- **Firebase Crashlytics** — automatic crash reporting for Flutter (both Android and iOS). Non-fatal errors logged via `FirebaseCrashlytics.instance.recordError()`.
- **Cloud Functions error logging** — structured logs to Cloud Logging; alert policies for function failures.

### Custom Analytics Events (Firebase Analytics)

Track major operations with custom events to build a usage dashboard:

| Event Name | Trigger | Key Parameters |
|---|---|---|
| `login` | Successful sign-in | `method` (google/apple) |
| `signup` | First-time user created | `method` |
| `program_created` | Program document created | `type` (assignable/personal) |
| `program_published` | Status → published | `programId` |
| `workout_completed` | Instance status → completed | `programId`, `workoutType`, `rpe` |
| `workout_missed` | Instance status → missed | `programId` |
| `enrollment_added` | Athlete enrolled | `programId` |
| `enrollment_removed` | Athlete removed | `programId` |
| `message_sent` | DM or comment created | `type` (dm/comment), `programId` |
| `exercise_created` | Exercise template created | — |
| `template_published` | Workout template version published | `workoutTemplateId`, `version` |
| `export_requested` | Athlete triggers data export | `format` (json/csv) |
| `feedback_submitted` | In-app feedback sent | `type` (bug/feature/general) |
| `timer_started` | Workout timer begins | `mode` (reps/time/amrap) |

### Dashboard

- **Google Analytics (linked to Firebase)** provides a free, real-time dashboard with user counts, event counts, retention, and funnels.
- **Custom BigQuery export** (free tier: 1 TB/month query) for deeper analysis if needed post-MVP.
- Key dashboard views:
  - Daily/weekly active users
  - Workout completions per day
  - Login count by method
  - Message/comment volume
  - Error rate (Crashlytics integration)
  - Feedback submission count and categories

---

## 12. In-App Feedback 🔒

### Feedback Collection

An in-app feedback form accessible from the profile/settings screen. Fields:

- **Type:** bug report / feature request / general feedback (required)
- **Body:** free text (required)
- **Screenshot:** optional external image URL
- **App context:** automatically captured (screen name, app version, OS, device model)

### Firestore Model

```
feedback/{feedbackId}
  userId: string
  type: string ("bug" | "feature" | "general")
  body: string
  screenshotUrl: string?
  appVersion: string
  platform: string ("android" | "ios")
  deviceModel: string
  screenName: string
  status: string ("new" | "reviewed" | "resolved" | "wont_fix")
  adminNotes: string?
  createdAt: timestamp
  updatedAt: timestamp
```

### Admin Visibility

- Feedback documents are **write-only for users** (they can create but not read others' feedback).
- An admin/owner dashboard view (web or in-app) lists all feedback sorted by recency, filterable by type and status.
- Feedback counts and trends appear on the observability dashboard alongside usage metrics.
- The `feedback_submitted` analytics event (Section 11) allows tracking submission volume without reading individual feedback documents.

---

## 13. Cloud Functions Inventory 🔒

Every Cloud Function in the system, its trigger, and what it does:

| # | Function Name | Trigger | Description | Feature Area |
|---|---|---|---|---|
| 1 | `onUserCreated` | `auth.user().onCreate` | Creates `users/{uid}` document with initial fields from Firebase Auth profile | Auth |
| 2 | `onTemplatePublished` | Firestore `onCreate` on `workoutTemplateVersions/{v}` | Queries `workoutInstances` with `status == "scheduled"` for that template, batch-updates `workoutTemplateVersion` to new version | Versioning |
| 3 | `markMissedWorkouts` | Cloud Scheduler (daily cron, e.g. 02:00 UTC) | Queries `workoutInstances` where `scheduledDate < today` and `status == "scheduled"`, sets `status: "missed"` | Schedule |
| 4 | `onEnrollmentRemoved` | Firestore `onUpdate` on `enrollments/{id}` (status → `removed`) | Writes `removedAt` timestamp, optionally cancels future scheduled instances | Enrollment |
| 5 | `exportUserData` | HTTPS callable | Generates JSON export of athlete's workout instances, load history, messages, and feedback; returns download URL | Data Portability |
| 6 | `onFeedbackCreated` | Firestore `onCreate` on `feedback/{id}` | Logs `feedback_submitted` server-side metric, optionally sends notification to admin channel | Feedback |
| 7 | `onUserDeleted` | `auth.user().onDelete` | Cascading cleanup: deletes/anonymizes user data across all collections (see below) | Auth / Privacy |
| 8 | `materializeRecurrence` | HTTPS callable | Expands a recurrence pattern + end date into individual `workoutInstances` documents in a batch write | Scheduling |
| 9 | `onProgramPublished` | Firestore `onCreate` on `programVersions/{v}` | Snapshots the program structure; optionally updates enrollments referencing the program to the new version based on owner's upgrade choice | Versioning |

### User Deletion Cleanup (onUserDeleted) — Detail

Triggered when a user deletes their account via Firebase Auth. The function cascades through all collections:

1. **`users/{uid}`** — delete document.
2. **`usernames/{username}`** — delete the username reservation doc.
3. **`enrollments`** — query all enrollments where `athleteId == uid`, set `status: "removed"`, write `removedAt`.
4. **`workoutInstances`** — query all instances where `athleteId == uid`, anonymize or delete based on data retention policy. Delete future scheduled items.
5. **`directMessageThreads`** — query threads where `athleteId == uid`, anonymize messages (replace senderId with "deleted-user") or delete.
6. **`workoutInstanceComments`** — query comments where `authorId == uid`, anonymize or delete.
7. **`feedback`** — query feedback where `userId == uid`, anonymize.
8. **`programs`** — query programs where `ownerId == uid`. If the user is an owner, mark programs as `"archived"` and notify enrolled athletes (post-MVP: transfer ownership flow).

**Failure handling:**

```
cleanupFailures/{failureId}
  userId: string
  functionName: string ("onUserDeleted")
  failedStep: string (e.g. "enrollments", "workoutInstances")
  error: string
  attemptCount: int
  lastAttemptAt: timestamp
  resolved: bool
  createdAt: timestamp
```

- If any step fails, the function logs the failure to `cleanupFailures` and continues with remaining steps (best-effort cascade).
- A **Cloud Monitoring alert** fires when any document is written to `cleanupFailures`, notifying the admin via email.
- An admin dashboard view lists unresolved cleanup failures for manual intervention.
- A retry mechanism (HTTPS callable `retryCleanup`) can re-attempt failed steps for a specific userId.

### Future Cloud Functions (Post-MVP)

| # | Function Name | Trigger | Description | Feature Area |
|---|---|---|---|---|
| 10 | `sendExpiryNotifications` | Cloud Scheduler (daily cron) | Checks enrollment durations, sends pre-expiry push notifications | Marketplace / Lifecycle |
| 11 | `autoRemoveExpired` | Cloud Scheduler (daily cron) | Writes `removedAt` on enrollments past expiry date | Marketplace / Lifecycle |
| 12 | `onForumReply` | Firestore `onCreate` on forum reply | Sends push notification to thread participants | Community / Forum |

---

## 14. Recurring Workout Scheduling 🔒

### Approach: bounded materialization with required end date

When a program owner assigns a recurring workout, the system requires an end date — no open-ended recurrences. All workout instances are created upfront via a batch write.

### How it works

1. Owner selects a workout and chooses schedule type: **one-off** or **recurring**.
2. For recurring, the owner sets:
   - **Pattern:** weekly, biweekly, or custom interval
   - **Days of week:** e.g., Monday + Wednesday + Friday
   - **End date:** required (e.g., "end of 8-week block" = 56 days out)
3. On save, the `materializeRecurrence` function (or client-side batch) expands the pattern into individual `workoutInstances` documents up to the end date.
4. Each materialized instance stores `recurrenceRootId` pointing back to the root instance, so they can be bulk-modified or cancelled together.

### Example

Owner assigns "Upper Pull Day" as recurring Mon/Wed/Fri from April 1 to May 24 (8 weeks):
→ System creates **24 workout instances** (3/week × 8 weeks) in a single batch.

### Modification

- **Cancel remaining:** owner can cancel all future instances in a recurrence (bulk delete by `recurrenceRootId` where `status == "scheduled"`).
- **Extend:** owner creates a new recurrence starting after the original end date.
- **Edit one:** owner modifies a single materialized instance without affecting siblings.

### Why no rolling/infinite recurrence

- Avoids a cron job that creates instances every week forever.
- Bounded materialization means all instances exist in Firestore at assignment time — no delayed creation, no race conditions.
- Keeps storage and cost predictable.
- Coach is forced to think in training blocks (which is better coaching practice anyway).

---

## 15. Resolved Decisions 🔒

All previously open decisions have been locked:

| # | Decision | Resolution |
|---|---|---|
| 1 | Cloud Functions language | **TypeScript (Node.js)** — mature ecosystem, best Firebase trigger support |
| 2 | Username uniqueness | **Client-side Firestore transaction** — atomic write to `usernames/{username}` + `users/{uid}`; transaction fails if username exists. No Cloud Function needed. |
| 3 | GoRouter route structure | **Flat routes with ShellRoute** — `ShellRoute` for bottom nav (Today, Programs, Messages, Profile); individual screens are flat routes (e.g., `/programs/:id`). Easy to refactor later. |
| 4 | Offline-first strategy | **Firestore built-in offline persistence** — SDK caches reads and queues writes automatically. No custom SQLite/Hive queue for MVP. Timer already runs locally. |
| 5 | Export format | **JSON only for MVP** — structured, lossless, simpler to generate. CSV deferred to post-MVP. |
| 6 | CI/CD pipeline | **GitHub Actions, deferred** — set up after first 2–3 features are working. Workflow: `flutter analyze` + `flutter test` + `firebase deploy --only functions` on push to `main`. Manual deploy during early dev. |

---

## 17. Estimated Firebase Costs

### Free Tier (Spark plan — $0/month)

The Spark plan covers the entire MVP development phase and likely early production for a small user base. Limits per project:

| Service | Free Allowance | Notes |
|---|---|---|
| **Firebase Auth** | Unlimited sign-ins | Google & Apple Sign-In have no per-auth charge on any plan |
| **Cloud Firestore — Storage** | 1 GiB total | Document data + indexes |
| **Cloud Firestore — Reads** | 50,000 /day | Each document fetch = 1 read |
| **Cloud Firestore — Writes** | 20,000 /day | Each document create/update = 1 write |
| **Cloud Firestore — Deletes** | 20,000 /day | |
| **Cloud Functions** | **Not available on Spark** | Requires Blaze plan (see below) |
| **Firebase Hosting** | 10 GiB storage, 360 MB/day transfer | Only relevant if serving a web dashboard |

> **Key limitation:** Cloud Functions require the Blaze (pay-as-you-go) plan. Since this app needs functions for user creation and auto-upgrade, you must upgrade to Blaze before deploying any backend logic.

### How to Set Up the Blaze Plan

1. Go to [console.firebase.google.com](https://console.firebase.google.com) and select (or create) your project.
2. Click the **Spark** plan badge in the bottom-left → **Upgrade**.
3. Select **Blaze (pay as you go)**.
4. Link or create a **Google Cloud Billing account** (requires a credit card).
5. Confirm — done. All free-tier allowances still apply.
6. **Immediately** set a budget alert in Google Cloud Console → Billing → Budgets & Alerts (e.g., $5/month during dev).

### Pay-as-you-go Tier (Blaze plan — usage-based, same free allowances first)

The Blaze plan still includes the same free allowances above — you only pay for usage that exceeds them. Pricing beyond the free tier:

| Service | Price beyond free tier |
|---|---|
| **Cloud Firestore — Reads** | $0.06 per 100K reads |
| **Cloud Firestore — Writes** | $0.18 per 100K writes |
| **Cloud Firestore — Deletes** | $0.02 per 100K deletes |
| **Cloud Firestore — Storage** | $0.18 /GiB/month |
| **Cloud Functions — Invocations** | First 2M/month free, then $0.40 per 1M |
| **Cloud Functions — Compute** | 400K GB-seconds/month free, then $0.0000025 per GB-second |
| **Cloud Functions — Networking** | 5 GB/month free outbound, then $0.12/GB |
| **Firebase Auth — Phone/SMS** | $0.01–0.06 per SMS (not used in this app) |

### Projected Cost at Scale Milestones

Estimates assume average usage patterns: ~10 Firestore reads and ~3 writes per user session, ~2 sessions/day per active user, ~1 Cloud Function invocation per workout completion.

| Active Users | Est. Monthly Firestore | Est. Monthly Functions | **Total** |
|---|---|---|---|
| **1–50** (dev/beta) | $0 (within free tier) | $0 (within free tier) | **$0** |
| **200** | ~$1–3 | ~$0 | **~$1–3** |
| **1,000** | ~$8–15 | ~$1 | **~$10–16** |
| **5,000** | ~$40–75 | ~$3–5 | **~$45–80** |
| **10,000+** | ~$80–150+ | ~$8–12 | **~$90–160+** |

### Cost Controls

- **Set a budget alert** in the Google Cloud Console (e.g. $5/month during beta, $25 during early launch).
- **Enable daily spending cap** via the Firebase billing page so unexpected spikes don't accumulate.
- **Use Firestore composite indexes** and query design to minimize unnecessary reads (every listener re-read counts).
- **Batch writes** where possible (e.g., bulk enrollment) to reduce write count.
- **Cache with Riverpod** — avoid re-fetching data already in memory.

### Bottom Line

Firebase Auth and Firestore are completely free for development and early users on the Blaze plan (the free allowances still apply). You'll need Blaze from day one because of Cloud Functions, but real charges won't begin until you meaningfully exceed the free tier — roughly **200+ active daily users** before you see a bill above $1/month.

---

## 16. Implementation Sequence (next steps)

Based on the roadmap and these locked constraints, the build order is:

1. **Project setup** — create the real app project (not the smoke test), add Firebase via FlutterFire CLI, configure Riverpod + GoRouter skeleton, set up feature folder structure.
2. **Auth end-to-end** — Google Sign-In → Firebase Auth → user doc creation (Cloud Function) → authenticated home screen.
3. **Exercise & workout template CRUD** — Firestore writes with versioning sub-collection, basic UI for program owners.
4. **Program creation & publishing** — create/draft/publish flow, program-workout mapping.
5. **Enrollment & scheduling** — enroll athletes, assign workouts to dates, create workout instances.
6. **Workout completion & load** — log actuals/RPE/duration, client-side load computation, dashboard widgets.
7. **Comments** — unified comments (program/workout/exercise scopes), direct message threads, media link preview.


8. **Athlete goals & to-do list** — athletes can create, view, and manage a personal list of goals or "to-dos". Each goal can have an optional due date. Goals are displayed in a checklist UI, can be checked off, and are shown on the same calendar as workouts. Goals are private to the athlete by default, but visibility to the program owner can be enabled per goal. Goals can optionally be associated with a specific program the athlete is enrolled in.

---


## Athlete Goals & To-Do List (MVP Phase)

### Overview

Athletes can create, view, and manage a personal list of goals or "to-dos" within the app. Each goal can have an optional due date. Goals are displayed in a simple checklist UI, allowing athletes to check off completed items. Goals with dates appear on the same calendar as scheduled workouts, providing a unified view of training and personal objectives.

**Visibility and Program Association:**
- By default, goals are private to the athlete. However, the athlete can optionally make a goal visible to the program owner of a program they are enrolled in (for accountability, feedback, or coaching).
- Each goal can optionally be associated with a specific program the athlete is part of. This allows both personal and program-specific goals to be tracked and surfaced in the appropriate context.


### Key Features

- **Create/Edit/Delete Goals:** Athletes can add new goals, edit existing ones, and remove goals from their list.
- **Completion Tracking:** Goals can be checked off when completed. Completed goals remain visible (with a checked state) until deleted.
- **Due Dates & Calendar Integration:** Goals can have an optional due date. Dated goals are shown on the athlete's calendar alongside workouts, with distinct visual markers.
- **Simple UI:** The to-do/goals screen is accessible from the main navigation or dashboard, with a clear add/check-off interaction.
- **Visibility Control:** Each goal has a setting to make it visible to the program owner of an associated program, or keep it private to the athlete.
- **Program Association:** Each goal can optionally be linked to a specific program the athlete is enrolled in, or left unassociated for general/personal goals.


### Data Model (Draft)

```
goals/{goalId}
  athleteId: string (userId)
  title: string
  notes: string?
  dueDate: string? (ISO 8601 date)
  completed: bool (default false)
  completedAt: timestamp?
  programId: string?           # optional, links to a program the athlete is enrolled in
  visibleToOwner: bool (default false)  # if true, visible to the program owner of associated program
  createdAt: timestamp
  updatedAt: timestamp
```


### Calendar Integration

- The calendar view aggregates both scheduled workouts and goals with due dates.
- Tapping a date shows both workouts and any goals due that day (including program-linked and personal goals).
- Overdue goals are visually indicated until checked off or deleted.
- Program owners can see due dates for goals that are both associated with their program and marked as visible by the athlete.

---

---

## 17. Rate Limiting 🔒

Rate limiting is enforced from day one at two layers: client-side (prevent accidental bursts) and server-side (prevent abuse regardless of client behavior).

### Client-Side Limits (Flutter app)

| Action | Mechanism | Limit |
|---|---|---|
| Comment / message send | Debounce on submit button | 1 per 2 seconds |
| Workout completion | Disable submit button after tap until write confirms | 1 per instance (idempotent) |
| Pull-to-refresh | Throttle refresh callback | 1 per 5 seconds |
| Feedback submission | Disable form after submit | 1 per 30 seconds |
| Username check | Debounce text input | 1 query per 500ms of typing pause |
| Enrollment (bulk) | Progress indicator + disable button | 1 batch operation at a time |

These are UX-level protections. They prevent double-taps and rapid resubmissions but cannot stop a modified client.

### Server-Side Limits (Firestore Security Rules)

Firestore Security Rules can enforce write frequency using a rate-limit helper document per user:

```javascript
// Rate limit helper: each user has a document tracking their last write time
match /rateLimits/{userId} {
  allow read, write: if isSelf(userId);
}

// Example: limit comment creation to 1 per 2 seconds
match /comments/{commentId} {
  allow create: if isSignedIn()
    && isAthleteOrOwner(request.resource.data.programId)
    && request.resource.data.authorId == request.auth.uid
    // Rate limit: last write must be >2 seconds ago
    && (!exists(/databases/$(database)/documents/rateLimits/$(request.auth.uid))
        || request.time > get(/databases/$(database)/documents/rateLimits/$(request.auth.uid)).data.lastCommentAt + duration.value(2, 's'));
}
```

The app updates `rateLimits/{userId}.lastCommentAt` on each comment write. The security rule checks the gap.

### Per-Action Server-Side Limits

| Action | Limit | Enforcement |
|---|---|---|
| Comments / messages | 1 per 2s per user | Security rule + `rateLimits` doc |
| Workout instance writes | 1 per 5s per user | Security rule + `rateLimits` doc |
| Feedback submission | 1 per 60s per user | Security rule + `rateLimits` doc |
| Username reservation | 1 per 10s per user | Security rule + `rateLimits` doc |
| Enrollment creation (owner) | 10 per minute per user | Security rule + `rateLimits` doc |
| HTTPS callable functions (`exportUserData`, `materializeRecurrence`) | Built-in Cloud Functions rate limiting (max concurrent invocations per user) | Cloud Functions config: `maxInstances` + per-user check in function code |

### Rate Limit Document

```
rateLimits/{userId}
  lastCommentAt: timestamp?
  lastWorkoutWriteAt: timestamp?
  lastFeedbackAt: timestamp?
  lastUsernameAttemptAt: timestamp?
  lastEnrollmentAt: timestamp?
  enrollmentCountLastMinute: int?
```

This is a single lightweight document per user, updated atomically alongside the action it gates. The security rule reads it via `get()` (counts as 1 Firestore read per gated write — minimal cost).

### Abuse Detection

- If a client bypasses app-level debouncing, the security rules still block rapid writes.
- Cloud Functions log repeated rate-limit rejections. A Cloud Monitoring alert can fire if a single user hits rate limits more than N times per hour, indicating a buggy or malicious client.

---

## 18. Known Future Risks 🔒

These are not blockers for MVP but are worth noting so they don't become surprise refactors.

| Risk | Impact | Mitigation |
|---|---|---|
| **Full-text search** | Firestore has no native full-text search. Exercise search, program discovery (marketplace), and username lookup will be limited to exact-match or prefix queries. | Acceptable for MVP (small catalog). Post-MVP: add Algolia, Typesense, or a Cloud Function that maintains a search index. |
| **Complex aggregation queries** | Dashboard widgets (load summaries, completion rates) require aggregating across many documents. Firestore doesn't have SQL-style GROUP BY. | Compute aggregates client-side from cached data for MVP. Post-MVP: use Firestore `count()` / `sum()` aggregation queries or maintain pre-computed aggregate documents. |
| **Push notifications delivery** | No push notification delivery mechanism is defined yet (FCM tokens, APNs). The `notifications` collection stores in-app notifications, but device push requires FCM integration. | Add FCM token storage to the user document and integrate `firebase_messaging` package when messaging ships. |
| **Image/video hosting** | External links work for MVP, but link rot, inconsistent previews, and no moderation control are risks if usage scales. | Post-MVP: add Firebase Storage or a CDN for user-uploaded media with content moderation. |
| **Rate limiting** | A malicious or buggy client could generate excessive writes. | **Mitigated from day one** — see Section 17. Client-side debouncing + server-side Firestore Security Rules with per-user rate-limit documents. |

---

### Workout Instance Status Transitions 🔒

```
  scheduled → completed    (athlete completes on time or late)
  scheduled → missed       (daily cron marks overdue)
  missed    → completed    (athlete recovers a missed workout)
```

When a missed workout is completed, `status` changes to `"completed"`, `completedAt` is written, and `missedAt` remains as a historical record showing it was originally missed. Load points are computed normally.

---

*End of document. Update version number and move sections from ❓ to 🔒 as decisions are made.*
