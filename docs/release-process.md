# Firebase release process

Mercedes uses separate Firebase projects for `dev`, `staging`, and `prod`.
Production is `mercedes-app-11ce2`. Development and staging intentionally have
no project IDs in `config/firebase-environments.json` until they are
provisioned. Every release command requires both an environment and a project
ID or matching CLI alias; there is no default alias.

## Stage 5 browser validation timeouts

`scripts/run-stage-validation.ps1` gives Flutter/web compilation and emulator
startup their existing 240-second process boundary. Once the Flutter test
runner starts the test body (or a test prints its first
`BROWSER_TEST_STEP_START` marker), the scenario has a separate 90-second
deadline. Individual navigation and condition waits use 15–30 second limits
and a two-second Flutter-pump limit, so a functional stall fails before the
outer process boundary. The recovery canary mounts the initial web root with
the known-good bounded `pumpWidget` startup step, then observes the login
surface through the normal named condition polling. Compilation remains
outside the scenario budget. To verify workout recovery, the canary navigates
away from the canonical workout route and reopens it within the stable app
root. It does not replace the integration binding's root widget as a proxy for
a browser reload.

Timeout diagnostics identify the deterministic identity, integration-test
file, current route when available, awaited condition, elapsed time, and
artifact directory. Functional failures and scenario timeouts are never
retried. The only automatic retry remains the single existing retry after all
functional smoke assertions pass but Chrome does not finish the optional
screenshot handshake within 20 seconds.

The validation runner starts each browser invocation in a Windows kill-on-close
job. Success, failure, or timeout closes that job and terminates only its owned
PowerShell, Firebase, ChromeDriver, and Chrome process tree by job/PID
ownership; unrelated processes and emulator sessions from other runs are not
name-killed.

Browser automation also starts Chrome with background timer throttling,
renderer backgrounding, and occluded-window backgrounding disabled. This keeps
Flutter Web frame scheduling and bounded test waits independent of whether the
Chrome window has focus. Existing caller-supplied Chrome flags are preserved
without duplicate options. App lifecycle behavior remains enabled, and
recovery tests still simulate lifecycle transitions explicitly.

## One-time staging provisioning

An owner with billing and project-creation permissions must complete these
steps manually. Do not clone production Firestore data.

1. Create an empty Google Cloud project with billing enabled.
2. Add Firebase resources:

   ```powershell
   firebase projects:addfirebase <staging-project-id>
   ```

3. In the Firebase console, create the default Firestore database in Native
   mode, enable Firebase Authentication's Email/Password provider, and create a
   Hosting site.
4. Register a web app and print its non-secret SDK configuration:

   ```powershell
   firebase apps:create WEB "Mercedes staging" --project <staging-project-id>
   firebase apps:sdkconfig WEB <staging-app-id> --project <staging-project-id>
   ```

5. Replace the staging `null` values in
   `config/firebase-environments.json`, add the real `staging` alias to
   `.firebaserc`, and commit that configuration. Never point `staging` or
   `dev` at `mercedes-app-11ce2`.
6. Create a dedicated release-canary service account with only the ability to
   manage Firebase Authentication users and the canary's Firestore documents.
   Store its JSON key outside the repository. Prefer workload identity
   federation instead of a long-lived key when this flow moves to CI.

The currently authenticated Firebase account can read only the existing
production project. It cannot prove that a staging project, billing link,
Firestore database, Auth provider, or web app exists. Provisioning remains a
manual owner action.

## Local secret and web configuration

Set these only in the release shell or a secret file excluded by Git:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\secure\mercedes-staging-canary.json'
$env:FIREBASE_WEB_API_KEY = '<staging web API key>'
$env:FIREBASE_WEB_APP_ID = '<staging web app ID>'
$env:FIREBASE_WEB_MESSAGING_SENDER_ID = '<staging sender ID>'
$env:FIREBASE_WEB_PROJECT_ID = '<staging-project-id>'
$env:FIREBASE_WEB_AUTH_DOMAIN = '<staging-project-id>.firebaseapp.com'
$env:FIREBASE_WEB_STORAGE_BUCKET = '<staging bucket>'
$env:FIREBASE_WEB_MEASUREMENT_ID = '<optional measurement ID>'
$env:RELEASE_CANARY_TRAINER_EMAIL = 'release-canary-trainer@<owned-domain>'
$env:RELEASE_CANARY_TRAINER_PASSWORD = '<secret>'
$env:RELEASE_CANARY_ATHLETE_EMAIL = 'release-canary-athlete@<owned-domain>'
$env:RELEASE_CANARY_ATHLETE_PASSWORD = '<secret>'
```

The seed and cleanup commands verify the selected environment, resolved CLI
alias, service-account `project_id`, Hosting URL, reserved
`release-canary-` namespace, and every ownership field before using Admin SDK
privileges. They never query, enumerate, or mutate non-canary user data.

### Public YouTube API setup

The public-channel browser requires an operator-managed YouTube Data API v3
key. It is not an OAuth credential and must never be placed in Flutter
`--dart-define` values, Firebase web configuration, source, or CI logs.

The recommended production path is the guarded operator script:

```powershell
# Read-only; exits nonzero with actionable diagnostics until every
# prerequisite and clean-main integration check passes.
.\scripts\setup-youtube-production.ps1 -CheckOnly

# Interactive setup. Every cloud mutation requires an exact typed phrase;
# dry-run and deployment both default to no.
.\scripts\setup-youtube-production.ps1
```

The script defaults to `prod` / `mercedes-app-11ce2`, accepts explicit
`-Environment`, `-Project`, and `-RequiredCommit` values, and enforces
`config/firebase-environments.json`. It verifies Git, gcloud, Firebase CLI,
authenticated project access, clean `main`, exact intended commit, and the
presence of locked Functions dependencies plus local `tsc`. When integration
is incomplete it only prints safe `git fetch`, `git switch main`, and
`git merge --ff-only` commands; it never merges, rebases, pushes, or
force-pushes. `-CheckOnly` reports missing Functions dependencies with the
exact recovery command and performs no cloud, dependency, or repository
mutation. On Windows, it first verifies real non-elevated symbolic-link
creation in a unique temporary directory and always removes the probe.
Check-only mode never opens Settings or changes Developer Mode. If the probe
fails, open it manually with `start ms-settings:developers`, turn on
**Developer Mode**, and rerun the check. Interactive mode offers to open that
page only after the exact `OPEN DEVELOPER SETTINGS` confirmation, then requires
`DEVELOPER MODE ENABLED` and rechecks the actual capability before continuing.

The script prints and attempts to open the exact Google Cloud Credentials URL.
If browser launch is unavailable, use the printed URL and continue at the
prompt. It never accepts the API key: Firebase CLI owns the secure value prompt
for `functions:secrets:set`. API enablement, key creation/restriction, secret
version creation, dependency installation, dry-run, and deployment remain
explicit operator decisions. If locked Functions dependencies are absent,
interactive mode requires the exact `INSTALL FUNCTIONS DEPENDENCIES` phrase
before running `npm --prefix functions ci --no-audit --no-fund`; it verifies
that `package.json` and `package-lock.json` did not change, verifies local
`tsc`, and builds before invoking Firebase. The repository local-tooling pin is
Node.js 24 while the deployed Functions runtime is Node.js 22, so the script
warns operators to use Node.js 22 for runtime-parity validation.

The Firebase backend dry run does not release a Functions or Firestore
revision. It is not fully non-mutating: Firebase CLI may enable required
service APIs such as Cloud Run or Eventarc, create service identities, or
prepare secret IAM. The script therefore labels it a cloud-preparation
mutation and requires the separate exact `DRY RUN <ENVIRONMENT>` phrase.
Actual deployment remains behind the later `DEPLOY <ENVIRONMENT>` gate.

The equivalent manual steps are:

1. In the exact Google Cloud project backing the target Firebase environment,
   enable **YouTube Data API v3**:

   ```powershell
   gcloud services enable youtube.googleapis.com --project <project-id>
   ```

2. Open the credentials page:

   ```text
   https://console.cloud.google.com/apis/credentials?project=<project-id>
   ```

   Create a server API key restricted to YouTube Data API v3. Apply the
   strongest supported application restriction for the deployed Functions
   environment and monitor the key in Google Cloud. Cloud Functions does not
   provide a stable outbound IP by default, so do not invent an IP restriction
   that would break production. The YouTube Data API restriction is mandatory;
   use a supported application restriction only when the environment provides
   a stable verifiable identity or egress boundary.
3. Store it as a Firebase Functions secret:

   ```powershell
   firebase functions:secrets:set YOUTUBE_API_KEY --project <project-id>
   ```

4. Confirm secret metadata without reading or printing the secret:

   ```powershell
   gcloud services list --enabled `
     --filter 'name:youtube.googleapis.com' `
     --format 'value(name)' `
     --project <project-id>
   firebase functions:secrets:get YOUTUBE_API_KEY --project <project-id>
   ```

5. Deploy Functions normally. Firebase binds the secret only to
   `youtubePublicLibrary`; no real key is required by unit, rules, or local
   browser tests. `deploy.ps1` performs the metadata check and fails before
   build/deploy when the secret is absent or inaccessible. A direct Firebase
   deployment also cannot create a healthy secret-bound revision without an
   accessible secret version. If a deployed revision is ever misconfigured
   with an empty value, the callable returns a sanitized
   `failed-precondition`; it never falls back to a client key or live
   unauthenticated proxy.

   On Windows, `deploy.ps1` performs the same real symbolic-link capability
   probe for Flutter projects with platform plugins before tests or builds. A
   failed probe exits immediately with `start ms-settings:developers` rather
   than failing later in Flutter tooling.

   After every requested target completes successfully on Windows,
   `deploy.ps1` prints one post-deployment reminder to run
   `start ms-settings:developers` manually and turn off only **Developer
   Mode**, while leaving normal Windows security protections enabled. It does
   not change the registry or any setting and does not open Settings
   automatically. The reminder is not printed for check-only or dry-run work,
   a declined, failed, or cancelled deployment, or a skipped Android build.
   Guided setup delegates this message to `deploy.ps1`, so it is printed only
   once when setup invokes a successful deployment.

   The operator script can invoke the documented backend dry run after a
   separate typed confirmation. The dry run does not release Functions or
   Firestore revisions, but may prepare cloud APIs, service identities, or IAM.
   It then prints the exact `deploy.ps1` command and can invoke it only after
   that dry run succeeds and the operator enters the unmistakable
   `DEPLOY PROD` confirmation; the default answer is always no. Explicit
   non-production environments use their corresponding uppercase environment
   name in both confirmation phrases.

To rotate the key, create a new API-restricted key, set it as a new secret
version, deploy only the callable, verify authenticated browsing, and then
disable the old key/version during a rollback window:

```powershell
firebase functions:secrets:set YOUTUBE_API_KEY --project <project-id>
firebase deploy --only functions:youtubePublicLibrary --project <project-id>
gcloud secrets versions list YOUTUBE_API_KEY --project <project-id>
gcloud secrets versions disable <old-version> `
  --secret YOUTUBE_API_KEY `
  --project <project-id>
```

After the rollback window, destroy the disabled Secret Manager version and
delete the old Google Cloud API key. Never print the key with
`functions:secrets:access`, place it in shell history, or commit it. Restoring
the prior secret version and redeploying the callable is the rollback path if
the new key fails verification.

The implementation never calls `search.list`. `channels.list`,
`playlistItems.list`, and `videos.list` each cost one unit, and the default
combined project allocation is 10,000 units per Pacific-Time day. Initial
indexing costs approximately one channel lookup plus two units per 50 uploads.
Incremental refresh normally costs the cached/one-unit channel resolution plus
two units per new uploads page until a known ID is reached. Full revalidation
uses two units per 50 uploads. Sources reviewed 2026-10-03:
<https://developers.google.com/youtube/v3/determine_quota_cost> and
<https://developers.google.com/youtube/v3/docs/playlistItems/list>.

Firestore counters cap YouTube calls at 8,000 units globally and 200 units per
UID per quota day, leaving operational headroom under 10,000. The callable
also permits 30 requests per authenticated UID per hour, validates query/sort/
page sizes, times upstream requests out after 8 seconds, and caps instances at
10. Shared channel generations eliminate duplicate per-user indexing. Cloud
Functions, Scheduler, Firestore operations, Secret Manager, and network usage
can incur charges under the configured billing plan.

**Deferred future policy; do not treat this as current behavior or a current
capacity guarantee:** cap initial indexing at the newest 1,000 public videos
per channel and store/display `availableCount`, `indexedCount`, and
`truncated`. Search and sort would cover the indexed newest 1,000 for an
oversized channel. Reserve roughly 20–30% of the shared 10,000-unit daily
project quota, leaving about 7,000–8,000 operational units. A worst-case new
1,000-video channel costs about 41 units (one channel lookup plus 20 uploads
pages and 20 video-detail batches), so plan for roughly 170–195 such channels
per day rather than 250. Keep the shared cache, incremental refresh,
per-channel job deduplication, and stale-generation fallback. A later explicit
**Index older videos** continuation must be budget-checked before it starts.

Fresh catalogues refresh after six hours and become visibly stale after 24
hours. Quota/upstream failures retain and explicitly label the prior active
generation. Incremental refresh minimizes calls; a full revalidation at least
every 25 days removes deleted/private uploads. The YouTube API Services
Developer Policies section III.E.4 requires public/non-authorized API data to
be refreshed or deleted within 30 days. The daily bounded
`cleanupYoutubeCatalogues` function recursively deletes expired catalogues;
no descriptions or thumbnail bytes are stored. Review policy revisions before
release: <https://developers.google.com/youtube/terms/developer-policies>.

The endpoint exposes public metadata only. It has no OAuth flow, refresh
tokens, private/unlisted access, arbitrary upstream URL proxying, or coupling
between Firebase Google sign-in and a YouTube channel. App Check is not yet
initialized in the current clients, so authentication, strict input
allowlisting, bounded requests, instance caps, and per-user rate limiting are
the active abuse controls. App Check enforcement should be added only with
coordinated client registration to avoid breaking legitimate traffic.
The callable runs in `us-central1` on the repository-pinned Node.js 22 runtime.
Firebase callable protocol CORS handling remains enabled, but Firebase
Authentication is required before secret/service initialization and the
allowlisted `resolve`/`videos` actions cannot proxy arbitrary URLs. App Check
is explicitly not enforced until every supported client initializes it; this
is a known staged-security boundary, not an implicit claim that App Check is
active.

Browser validation requires Google Chrome. The stage, browser-smoke, and
release-canary runners share one ChromeDriver resolver. It honors an explicit
`-ChromeDriverPath`, then `CHROMEDRIVER_PATH`, then `PATH`; otherwise it
provisions the matching Chrome for Testing driver into
`%LOCALAPPDATA%\Copilot\Mercedes\ChromeDriver` and reuses that cache. Supplied
and cached drivers are rejected when their major version differs from Chrome.
The download is runtime-selected rather than pinned in the repository tooling
inventory.

## Manual staging release

Run this sequence from a clean `main` checkout. Substitute the provisioned
project ID if the `staging` alias has not yet been committed.

```powershell
# 1. Fast checks.
node --test .\scripts\release\test\*.test.js
npm --prefix .\test-rules test

# 2. Complete local stage matrix.
.\scripts\run-stage-validation.ps1 -Stage stage5

# Optional: exercise the deployed-canary login/seed/browser/cleanup path
# entirely against local emulators before using staging.
.\scripts\test-release-canary-emulator.ps1

# 3. Read-only pre-release parity report. A mismatch is expected when this
#    commit intentionally changes rules/indexes; review every reported delta.
.\scripts\verify-deployed-config.ps1 `
  -Environment staging `
  -Project staging

# 4. Build against staging config, deploy Functions + Firestore configuration
#    with the required retry-policy acknowledgement, wait for all indexes,
#    deploy Hosting, then verify parity.
.\deploy.ps1 `
  -Target web `
  -StageDir stage5 `
  -Environment staging `
  -Project staging `
  -EnableReleaseCanaryLogin

# 5. Seed only the fixed synthetic namespace and run the deployed app canary.
.\scripts\seed-release-canary.ps1 `
  -Environment staging `
  -Project staging `
  -AppUrl https://<staging-project-id>.web.app
.\scripts\run-release-canary.ps1 `
  -Environment staging `
  -Project staging `
  -AppUrl https://<staging-project-id>.web.app

# 6. Verify the active rules/indexes after release. Cleanup is optional.
.\scripts\verify-deployed-config.ps1 `
  -Environment staging `
  -Project staging
.\scripts\cleanup-release-canary.ps1 `
  -Environment staging `
  -Project staging `
  -AppUrl https://<staging-project-id>.web.app
```

`deploy.ps1` passes `--force` only to the combined Functions and Firestore
deployment. Firebase requires this explicit acknowledgement because the
existing `onProgramVersionPublished` function has a failure/retry policy.
That trigger is designed to be retryable and idempotent: its durable
propagation state, operation identity, and ownership checks make repeated
invocations safe. The flag is not applied to Hosting and does not replace the
index-readiness or deployed-parity gates.

The browser canary signs in through the deployed web app as the dedicated
trainer and athlete. Release-canary mode exposes a narrowly gated DOM event
bridge that passes the supplied credentials directly to the Flutter login
flow and invokes the normal Firebase email/password sign-in path. This
avoids unreliable WebDriver typing into Flutter Web's transient semantics
inputs; credentials are removed from DOM attributes synchronously after the
event and authentication is never bypassed. The canary verifies the selected
Firebase project and header
identity, then checks backend-backed trainer Clients, Exercise Library,
Workout Library, Program Library, and Calendar/Assignments plus Athlete
Calendar, My Programs, and Workout History. Each surface must expose the exact
seeded synthetic record name; trainer calendar additionally proves the
athlete, program, and workout assignment tuple. Permission errors, app errors,
missing templates, and empty results fail the run.

The local emulator canary additionally compiles
`FAKE_PUBLIC_YOUTUBE_CATALOGUE=true`; it never calls YouTube. It verifies
catalogue completion/freshness, searches and sorts the complete fake
catalogue, edits the seeded exercise, invokes the same
attachment/save commands through a debug/emulator/query/fake-catalogue-gated
browser bridge for a drag-equivalent path and a distinct Select/Attach
replacement, saves/reopens, verifies thumbnail controls and exact immutable
version documents (including canonical URL) through the emulator Admin SDK,
and retains `trainer-exercise-youtube-drag.png` plus
`trainer-exercise-youtube-select.png`.

Successful PNG directories are retained as diagnostic release artifacts and
must remain in the worktree after validation. They are gitignored and must not
be committed. Cleanup may remove logs, temporary process output, Firebase
caches, generated plugin noise, and failed transient attempts only.

### Public YouTube release and rollback checks

The web release order is deliberate:

1. Confirm the secret metadata and build/test Functions.
2. Deploy all Functions (callable plus cleanup schedule), Firestore rules, and
   Firestore indexes together.
3. Wait until every index is ready.
4. Deploy Hosting.
5. Verify deployed Firestore rule/index parity.
6. Sign in as a real test user and resolve a known public channel; verify that
   quota, not-found, and unavailable errors remain sanitized.
7. Confirm `cleanupYoutubeCatalogues` is enabled with its daily
   `America/Los_Angeles` schedule and inspect callable/cleanup error logs.

Before the real release, validate the backend configuration without releasing
new Functions or Firestore revisions:

```powershell
firebase deploy `
  --only 'functions,firestore:rules,firestore:indexes' `
  --project <project-id> `
  --dry-run `
  --force
```

This command is a cloud-preparation mutation: Firebase CLI may enable required
service APIs, create service identities, or prepare IAM even with `--dry-run`.
Run it only after reviewing those possible project changes and explicitly
confirming them.

No new composite index is required: catalogue page reads use one generation
equality filter and server-side in-memory sorting over bounded page documents.
If the backend deployment fails, Hosting is not deployed. If index readiness
fails, Hosting is not deployed. If Hosting fails after the backend succeeds,
the prior client remains live against the backward-compatible callable/rules;
fix Hosting or redeploy the prior backend commit. If post-release YouTube
verification fails, redeploy the previous Functions revision and secret
version before rolling back Hosting. Do not remove the cleanup schedule while
catalogue documents from this revision remain; disable/delete it only after
the catalogue collection is empty. Firestore exercise version documents
remain immutable throughout.

The parity helper compares deployed Firestore rules and indexes; it does not
prove a Functions revision, secret value, API enablement, Hosting asset, or
YouTube quota. The secret metadata preflight, Firebase dry run, deployed
callable smoke, retained browser screenshots, and Firestore version assertions
cover those separate surfaces. No repository command creates the API key or
commits a secret.

### Branch integration ordering

The shared catalogue implementation is one Stage 5 topic change spanning the
callable/scheduled Functions, Firestore rules, Flutter contract/UX, tests, and
documentation. Do not cherry-pick only one surface: old clients remain
callable-compatible, but partial rules/backend/client integration would leave
the release unverified. Keep Stage 4 unchanged, integrate the topic branch to
`main` with the repository-required fast-forward-only workflow, then rerun the
complete validation boundary from the exact integrated commit before deploy.

## Production promotion

Promote the exact validated commit and repository Firebase configuration.
Production deployment remains explicit:

```powershell
.\deploy.ps1 `
  -Target web `
  -StageDir stage5 `
  -Environment prod `
  -Project prod
```

Production canaries are disabled by default at both build and runner layers.
Only an approved exceptional run may compile the form and pass the separate
production opt-in:

```powershell
.\deploy.ps1 `
  -Target web `
  -StageDir stage5 `
  -Environment prod `
  -Project prod `
  -EnableReleaseCanaryLogin `
  -AllowProductionCanary

.\scripts\seed-release-canary.ps1 `
  -Environment prod `
  -Project prod `
  -AppUrl https://mercedes-app-11ce2.web.app `
  -AllowProduction

.\scripts\run-release-canary.ps1 `
  -Environment prod `
  -Project prod `
  -AppUrl https://mercedes-app-11ce2.web.app `
  -AllowProduction

.\scripts\cleanup-release-canary.ps1 `
  -Environment prod `
  -Project prod `
  -AppUrl https://mercedes-app-11ce2.web.app `
  -AllowProduction
```

Do not seed or run a production canary without explicit release approval.

## Protected CI follow-up

Keep this flow manual until staging is provisioned and stable. A later
protected workflow should use an environment approval gate, workload identity
federation, masked canary credentials, immutable commit checkout, concurrency
locking, artifact retention, guaranteed cleanup, and the same scripts above.
It must never use production secrets in a staging job or infer a project from
Firebase CLI's active selection.
