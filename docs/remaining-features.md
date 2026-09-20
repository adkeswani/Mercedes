# Remaining Product Roadmap

This document is the current source of truth for unfinished product
implementation. Detailed schemas and historical decisions remain in
[`domain-model-design.md`](domain-model-design.md),
[`technical-design.md`](technical-design.md), and
[`mvp-architecture-plan.md`](mvp-architecture-plan.md). Raw customer context
remains in [`USER_FEEDBACK.md`](../USER_FEEDBACK.md).

## Current baseline

Stage 5 already provides authenticated Athlete and Trainer workspaces,
owner-scoped versioned exercise/workout/program templates, trainer-client
relationships, assignment and subscription propagation foundations, immutable
completed history, athlete calendar/program/history read surfaces, and the
bounded Trainer activity dashboard.

Trainer Exercise, Workout, and Program libraries have folders, Unfiled groups,
tags and tag filters, persistent collapsible sections, and explicit
client-scoped workout/program groups. That work began at `db72c30`, received UI
polish through `b3823fc`, and is merged to `main` and deployed. Automatic,
cached ChromeDriver provisioning is also complete for browser and release
validation.

These foundations do not make the workflows below complete.

## Prioritized remaining work

| Status | Scope | Dependencies | Acceptance summary |
| --- | --- | --- | --- |
| **Next** | **Trainer client workspace** | Existing relationship, instance, library, calendar, and history repositories | One client hub exposes schedule, active and past programs, independent workouts, activity, notes/forms/messages, and common actions without crossing ownership boundaries. |
| **Next** | **Trainer create/edit/assignment workflows** | Client workspace; existing immutable versions and copy/subscription rules | Trainers can create or edit from shared/client context, assign or schedule workouts/programs, use **Add next**, resolve overlaps, copy between clients, import one workout/program into another, and promote client content to a reusable template without mutating history. Program phases and main/add-on presentation must use the existing extensible model or a documented minimal extension. |
| **Next** | **Athlete Today and workout completion refinement** | Existing workout detail, typed slots, transactional completion, notes/discussions | Today clearly groups the next work by program; athletes can review media/instructions, record all supported actuals, RPE and duration, resume safely, validate, submit, and review completion. Timers and climbing-grade/color controls need production-ready authoring and completion UX. |
| **Next** | **Workout-history cursor pagination** | Existing `(athleteId, scheduledDate)` query/index | History loads bounded pages with stable cursors, retry/empty/error behavior, no duplicates or gaps, and immutable detail access across page boundaries. |
| **Next** | **Mutation-focused browser E2E** | Stable workflows above; existing emulator fixtures and automatic ChromeDriver | Cover create/edit, client scope, assignment, subscription propagation, completion, comment/reaction writes, relationship ending, immutable-history rejection, and cross-owner/athlete permission denial. Preserve deterministic screenshots and failure artifacts. |
| **Planned** | **Athlete Progress** | Completion data; load strategy/version semantics; bounded aggregation approach | Replace the placeholder with weekly load, workout-type distribution, difficulty mix, history trends, and transparent source/access context. Provide the JSON training-data export defined by the architecture plan. |
| **Planned** | **Messages and community UX** | Existing discussion/reaction authorization; notification and rate-limit decisions | Deliver direct trainer-athlete messaging outside a workout plus complete workout comment/reply/reaction surfaces. Support external photo and YouTube URLs with safe link previews; this is distinct from importing YouTube content into the exercise library. |
| **Planned** | **Dashboard lifecycle and adherence events** | A defined activity-event/projection contract | Add assignment, missed/adherence, program-transition, and other useful lifecycle events with bounded queries and deduplication. Add personal-best events only after comparator, tie, grading-system, and event semantics are implemented and tested. |
| **Planned** | **Mobile-specific UX** | Stable desktop workflows and a role/device capability matrix | Add phone-sized navigation and browser coverage, fast workout viewing/completion, lightweight exercise/workout creation and editing while coaching, media capture/linking, and permitted athlete adjustments. Device size must not change authorization. |
| **Planned** | **Goals/to-do calendar integration** | Athlete calendar aggregation and owner-visibility policy | Athletes can create, edit, complete, and delete private goals; optional due dates appear beside workouts, overdue goals are clear, and any trainer-visible program goal requires explicit athlete consent. |
| **Planned** | **Account privacy and portability** | Retention policy; relationship/history ownership decisions; retryable server orchestration | Add **Delete My Account** with explicit confirmation and disclosure, deterministic relationship detachment, deletion/anonymization of owned personal data, and documented retention of anonymized historical records. Export behavior must cover training data now and communication data when messaging ships. |
| **Planned** | **YouTube account and bulk exercise import** | YouTube authorization/API choice; import job state; quota/error handling | Connect a YouTube account, list and preview its videos in bulk, select one or many, import metadata, review duplicates, correct names/types, add tags, and attach/import selected videos into exercise content. This must be a real account/library workflow, not merely pasting individual YouTube URLs. |
| **Planned** | **Other imports and external services** | Provider selection and explicit integration state machines | Add CSV exercise import with validation/deduplication; identify and integrate the waiver service, block access until required signing is complete, and save signed forms to Dropbox or a documented off-platform destination; integrate payment-site signup/account linking with verified mismatch recovery rather than implicit email matching. |
| **Planned** | **Appointments, branding, and staff discovery** | Product decisions for ownership, visibility, and tenancy | Define in-person appointment calendar behavior, trainer branding surfaces, and the staff-under-primary-trainer permission model before implementation. Staff sharing must not weaken template/client ownership checks. |
| **Later** | **Marketplace and access lifecycle** | Discovery/search strategy; duration, consent, waiver, expiry, and notification semantics | Users can discover programs; duration-based access and pre-expiry notices are enforced; removal is auditable; completed history remains available according to policy. |
| **Later** | **Payments and entitlements** | Payment/account-linking integration; marketplace lifecycle | Paid Program Owner entitlement gates assignable-program creation without restricting athlete-personal programs. Billing state changes and failures are explicit and retryable. |
| **Later** | **Groups and broader community** | Group membership/ACL model; notification and export support | Group plans expose appropriate shared progress and group comments without leaking private athlete data. Program forums, replies, unread indicators, and community export follow the same boundaries. |
| **Later** | **Offline and richer media** | Conflict policy; storage/moderation decision | Preserve workout drafts offline and reconcile safely. Revisit app-hosted photo/video only when storage, retention, moderation, and cost policies are defined. |
| **Deferred** | **Separate staging Firebase project** | Owner provisioning and credentials | Optional release infrastructure, not a product-feature blocker. Local emulator validation, production parity checks, and ordered deployment remain required while staging is unprovisioned. |

## Sequencing rules

- Preserve explicit ownership, active-relationship checks, immutable versions,
  and completed-history protections in every new mutation.
- Prefer completing end-to-end client and athlete workflows before adding new
  top-level destinations.
- Add exact Firestore rule tests and deterministic browser mutation coverage
  with each workflow rather than deferring authorization validation.
- Do not treat placeholders, model support, or read-only screens as completed
  product features.
