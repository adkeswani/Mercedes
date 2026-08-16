# User Feedback

Use this file to record feedback, context, and follow-up actions.

## Feedback entries

### 2026-08-14 - Trainer and athlete experience

| Priority | Feedback |
| --- | --- |
| P0 | Split the app into two views: trainer and athlete. |
| P0 | Integrate Trainerize with YouTube so users do not have to copy links manually. |
| P1 | Add a dashboard showing each athlete's name, completed workouts, comments, workout difficulty, and an option to react. |
| P1 | Include messages and a client list in the dashboard view. |
| P1 | Add libraries for programs, workouts, exercises, forms, and related resources. |
| P1 | Add required waiver signing before users can continue, with signed legal forms automatically saved to Dropbox; consider whether signing can happen off-platform. |
| P2 | Add a dashboard showing personal bests and when athletes reach the end of a program. |
| P2 | Add branding support. |
| Not specified | Support other trainers working underneath the primary trainer. |
| Not specified | Add a calendar for in-person appointments. |
| Not specified | Integrate the payment website with the app to create accounts automatically and make linking less clunky. |
| Not specified | Add tags for clients. |
| Not specified | Organize workouts into folders and support workout tags. |
| Not specified | Support both shared and personal workouts. |
| Not specified | From a client's profile, show a list of their past programs. |
| Not specified | Maintain a master program list containing reusable templates. |
| Not specified | Distinguish between main programs and add-on programs. |
| Not specified | Allow the calendar to be filtered by program. |
| Not specified | Provide an "Add next" action for assigning the next program. |
| Not specified | Support importing a workout into another workout, importing programs, importing a client's program, and searching or filtering imported content. |
| Not specified | Allow programs to be created either from a client or from the global master program list. |
| Not specified | Support dragging exercises into a workout. |
| Not specified | Make it easy to save a client-level program to the master program list. |
| Not specified | Support phases within programs. |
| Not specified | Preserve master programs when switching a client to a different program, unlike Trainerize where the master can be lost. |
| Not specified | Import all YouTube content in one operation. |
| Not specified | Support editing programs and workouts on the mobile app during training, while retaining the laptop workflow. |
| Not specified | Allow workouts to be created from a phone. |
| Not specified | Support bouldering-specific grades in workouts. |
| Not specified | Support multiple workout types, including regular, circuit, and forced-timer interval workouts. |
| Not specified | Do not require instructions or descriptions when creating exercises. |
| Not specified | Support multiple exercise types, including strength, cardio, and bouldering-grade exercises. |
| Not specified | Allow photos as well as videos to be attached to exercises. |
| Not specified | Support importing exercises from CSV files. |
| Future | Add groups. |

**Status:** Captured

## Next steps and distilled actions

- Build distinct desktop and mobile experiences:
  - Desktop: full program, workout, and exercise creation.
  - Mobile: workout viewing and completion, plus basic creation and updates.
- Separate trainer and athlete roles, navigation, and permissions.
- Add a client list with access to each client's programs, history, messages, and activity.
- Design the hierarchy for clients, programs, workouts, exercises, folders, and tags.
- Add workflows for moving or importing content between clients, templates, programs, workouts, and exercises.
- Include the full program lifecycle in the desktop workout creation experience:
  - Master templates and client-specific programs.
  - Main and add-on programs.
  - Program phases.
  - Past-program history.
  - "Add next" assignment.
  - Saving client programs as reusable templates.
- Add bulk YouTube import and easier video attachment.
- Support different workout formats, including timed intervals, and climbing-specific route difficulties and colors.
- Build a dashboard for completions, comments, difficulty, reactions, programs nearing completion, and personal bests.
- Identify the client's current waiver service and its integration options.
- Investigate website-to-app account provisioning using the customer's Gmail address as the shared identity.
- Define how payment-site email changes, mismatches, and non-Gmail addresses should be handled.
- Build reusable libraries of exercises, workouts, and programs to support creation, assignment, copying, and customization flows.

## Example scenarios and target flows

### Onboarding and account access

- **New trainer joins the app:** Create an account, choose the trainer role, complete business/profile setup, optionally import existing content, create or connect a client list, and land on a desktop dashboard with clear next actions.
- **New athlete joins the app:** Create or claim an account, choose or confirm the athlete role, complete required profile and waiver steps, connect to a trainer, and land on today's schedule.
- **Athlete signs up on a trainer's website:** Submit the same email address used for app login, complete payment, receive an invitation or account-linking message, authenticate in the app, resolve any email mismatch, complete required forms, and appear in the trainer's client list.
- **Existing athlete connects to another trainer:** Accept an invitation, clearly see which data is shared with the new trainer, preserve personal history, and keep trainer-owned libraries and assignments separated.

### Athlete training

- **Athlete checks today's schedule:** Open the mobile app to a Today view, see scheduled workouts grouped by program, review status and trainer notes, and open the next workout in one tap.
- **Athlete completes a workout:** Open the workout, review instructions and media, record each exercise's results, use workout-specific controls such as interval timers or climbing grades/colors, add comments and difficulty, resume after interruption, then review and submit the completed workout.
- **Athlete self-assigns a workout from a trainer's program:** Browse workouts the trainer has made self-assignable, filter or search the library, preview a workout, select a date, confirm assignment, and retain the source program relationship.
- **Athlete reaches the end of a program:** See an advance warning, review progress and personal bests, receive the trainer's next-program decision or recommendations, and transition without losing history or access to completed work.
- **Athlete needs to adjust a workout on mobile:** Make permitted basic changes, such as substitutions, load, repetitions, schedule, or notes, while clearly distinguishing athlete changes from the trainer's original template.

### Trainer content creation

- **Trainer creates a new exercise:** Start from the exercise library, search before creating to avoid duplicates, select an exercise type, add only the fields relevant to that type, attach or import media, add tags and climbing metadata where applicable, then save it as personal or shared content.
- **Trainer imports exercises from YouTube:** Import one or many YouTube links, review extracted details, fix duplicates or missing metadata, assign tags and exercise types, and save the results to the exercise library.
- **Trainer creates a new workout:** Start from a blank workout, template, client workout, or imported workout; drag exercises from the library; select a workout format; configure sets, intervals, grades, and instructions; preview the athlete experience; and save it as personal or shared content.
- **Trainer creates a new program:** Start from a blank program, master template, or client program; define phases; add main and add-on workouts; configure scheduling and progression; preview the calendar; and save it as a master template or client-specific program.
- **Trainer creates content while coaching on mobile:** Make a lightweight exercise or workout, capture notes and media quickly, assign it to the current athlete, and optionally finish its metadata later on desktop.

### Trainer assignment and client management

- **Trainer assigns a program to an athlete:** Open the client, review current and past programs, select or create a program, choose start date and schedule, resolve overlap with existing assignments, customize without changing the master template, and confirm what the athlete will see.
- **Trainer schedules the next program:** Use an "Add next" action before the current program ends, choose or build the successor, preview the transition, and notify the athlete.
- **Trainer copies content between athletes:** Open an athlete's exercise, workout, or program; choose Copy or Save as template; select another athlete; review ownership and linked-content behavior; customize the copy; and assign it without mutating the source athlete's history.
- **Trainer promotes client content to a library:** Save a useful client-specific exercise, workout, or program as a reusable personal or shared template while preserving the original assignment and history.
- **Trainer reviews athlete activity:** Open the dashboard, filter by client, program, or date, review completions, comments, difficulty, reactions, personal bests, and programs nearing completion, then message the athlete or adjust upcoming work.
- **Trainer manages clients:** Search and tag the client list, open a client workspace containing schedule, active and past programs, activity, messages, forms, and notes, and take common assignment actions without navigating through unrelated screens.

### Exceptions and recovery

- **Payment email does not match app login:** Explain the mismatch, allow a safe verification or trainer-assisted resolution flow, and prevent duplicate athlete records.
- **Trainer changes a master template:** Ask whether changes apply only to the template, future assignments, or selected active client programs; never silently overwrite completed or customized work.
- **Athlete loses connectivity during a workout:** Preserve progress locally, allow completion offline where possible, and sync with clear conflict handling when connectivity returns.

## Unifying product structures

### Content and execution hierarchy

Use reusable templates to create athlete-specific assignments and immutable results:

```text
Exercise Library
  -> Workout Templates
    -> Program Templates
      -> Athlete Program Assignment
        -> Scheduled Workout Instance
          -> Exercise Results
```

- **Libraries instead of rigid folders:** Store exercises, workouts, and programs in searchable libraries with tags, ownership, sharing scope, folders, and saved views. Folders organize content but do not determine ownership.
- **Templates and instances:** Keep reusable definitions separate from assigned and completed work. Editing a template must not silently alter customized assignments or historical results.
- **Client workspace:** Give each client one hub for their schedule, active and past programs, results, messages, forms, notes, and common assignment actions.
- **Copy, customize, and promote:** Allow eligible content to be copied to another client, customized without changing its source, or promoted into a reusable template.
- **Role and device capability matrix:** Let trainer or athlete role determine permissions, while desktop or mobile determines interaction depth. A device type should not imply a user role.
- **Composable workout blocks:** Represent strength sets, timed intervals, circuits, climbing routes, and future formats as typed blocks within one workout system.
- **Program lifecycle:** Track programs through draft, active, nearing completion, and completed states, with phases, main and add-on programs, and a queued next program.
- **Activity event stream:** Record completions, comments, difficulty, reactions, personal bests, assignments, and program lifecycle events. Build dashboard views and notifications from this stream.
- **Explicit ownership and visibility:** Distinguish personal, trainer-shared, client-specific, and system content, with ownership and mutation permissions enforced for every write.
- **Integration state machines:** Represent payment signup, account linking, invitations, and waivers with explicit states such as pending, matched, action required, and complete instead of relying on implicit email matching.
