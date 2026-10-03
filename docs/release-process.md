# Firebase release process

Mercedes uses separate Firebase projects for `dev`, `staging`, and `prod`.
Production is `mercedes-app-11ce2`. Development and staging intentionally have
no project IDs in `config/firebase-environments.json` until they are
provisioned. Every release command requires both an environment and a project
ID or matching CLI alias; there is no default alias.

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

1. In the exact Google Cloud project backing the target Firebase environment,
   enable **YouTube Data API v3**:

   ```powershell
   gcloud services enable youtube.googleapis.com --project <project-id>
   ```

2. Create a server API key restricted to YouTube Data API v3. Apply the
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

Each channel resolution uses one `channels.list` quota unit. Each uncached
uploads page normally uses one `channels.list`, one `playlistItems.list`, and
one batched `videos.list` call. Instance-local channel metadata is cached for
10 minutes and page metadata for 5 minutes; cold starts do not retain cache.
The callable accepts at most 50 videos per page, times upstream requests out
after 8 seconds, caps instances at 10, and permits 30 calls per authenticated
user per hour using server-owned Firestore rate-limit records. Search and sort
operate only over the catalogue pages loaded by the client. YouTube project
quota and Cloud Functions/Firestore/network usage can incur charges under the
configured Google Cloud billing plan.

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
trainer and athlete. It verifies the selected Firebase project and header
identity, then checks backend-backed trainer Clients, Exercise Library,
Workout Library, Program Library, and Calendar/Assignments plus Athlete
Calendar, My Programs, and Workout History. Each surface must expose the exact
seeded synthetic record name; trainer calendar additionally proves the
athlete, program, and workout assignment tuple. Permission errors, app errors,
missing templates, and empty results fail the run.

The local emulator canary additionally compiles
`FAKE_PUBLIC_YOUTUBE_CATALOGUE=true`; it never calls YouTube. It edits the
seeded exercise, searches and sorts the fake catalogue, invokes the same
attachment/save commands through a debug/emulator/query/fake-catalogue-gated
browser bridge for a drag-equivalent path and a distinct Select/Attach
replacement, verifies the exact immutable version documents through the
emulator Admin SDK, and retains `trainer-exercise-youtube-drag.png` plus
`trainer-exercise-youtube-select.png`.

Successful PNG directories are retained as diagnostic release artifacts and
must remain in the worktree after validation. They are gitignored and must not
be committed. Cleanup may remove logs, temporary process output, Firebase
caches, generated plugin noise, and failed transient attempts only.

### Public YouTube release and rollback checks

The web release order is deliberate:

1. Confirm the secret metadata and build/test Functions.
2. Deploy Functions, Firestore rules, and Firestore indexes together.
3. Wait until every index is ready.
4. Deploy Hosting.
5. Verify deployed Firestore rule/index parity.
6. Sign in as a real test user and resolve a known public channel; verify that
   quota, not-found, and unavailable errors remain sanitized.

Before the real release, validate the backend configuration without mutation:

```powershell
firebase deploy `
  --only 'functions,firestore:rules,firestore:indexes' `
  --project <project-id> `
  --dry-run `
  --force
```

If the backend deployment fails, Hosting is not deployed. If index readiness
fails, Hosting is not deployed. If Hosting fails after the backend succeeds,
the prior client remains live against the backward-compatible callable/rules;
fix Hosting or redeploy the prior backend commit. If post-release YouTube
verification fails, redeploy the previous callable and secret version before
rolling back Hosting. Firestore version documents remain immutable throughout.

The parity helper compares deployed Firestore rules and indexes; it does not
prove a Functions revision, secret value, API enablement, Hosting asset, or
YouTube quota. The secret metadata preflight, Firebase dry run, deployed
callable smoke, retained browser screenshots, and Firestore version assertions
cover those separate surfaces. No repository command creates the API key or
commits a secret.

### Branch integration ordering

The public YouTube work is self-contained in commits `7b87fd9` and `9c7218a`
plus this deployment-readiness commit. It does **not** depend on builder commit
`904fea0`, which is not an ancestor of this branch. Do not merge that unrelated
builder branch merely to deploy YouTube.

Both branches edit `docs/domain-model-design.md`,
`docs/remaining-features.md`, `docs/technical-design.md`, `firestore.rules`,
`stage5/README.md`, and `test-rules/firestore-rules.test.ts`. If both features
are approved for the same release, land the builder change first, then rebase
or cherry-pick the YouTube commits onto the updated `main`; resolve those six
files additively and rerun Functions, rules, Stage 5, and release-helper gates.
Deploy only from the resulting clean `main` commit. If builder is not approved,
integrate the YouTube commits directly without it.

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
