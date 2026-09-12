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

# 4. Build against staging config, deploy Functions + Firestore configuration,
#    wait for all indexes, deploy Hosting, then verify parity.
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

The browser canary signs in through the deployed web app as the dedicated
trainer and athlete. It verifies the selected Firebase project, header
identity, trainer route, Athlete Calendar, My Programs, and Workout History.
Each athlete surface must expose the exact seeded record name. Permission
errors, app errors, missing templates, and empty results fail the run.
Screenshots are retained only as diagnostic artifacts.

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
