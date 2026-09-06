---
name: stage-completion-testing
description: Run the complete validation matrix before declaring a stage complete.
---

# Stage completion testing

Use this skill whenever work in a `stageN/` directory is ready to be declared
complete.

## Required workflow

1. Run the repository validation entry point from the repository root:

   ```powershell
   .\scripts\run-stage-validation.ps1 -Stage stage5
   ```

   Omit `-Stage` to select the highest numbered stage automatically.

2. The command must complete all of these gates:
   - `flutter pub get`
   - the stage's complete `flutter test` suite
   - `flutter analyze --no-fatal-infos`
   - the root Firestore emulator rules suite, when `test-rules/` exists
   - every `integration_test/*_test.dart` file in the stage, once as the
     deterministic trainer and once as the deterministic athlete

   Browser runs have a four-minute process timeout and one explicit retry for
   a transient ChromeDriver screenshot-handshake timeout after the test
   assertions pass. Functional failures are not retried, and a second
   handshake timeout blocks stage completion.

3. Treat any failed command as a blocked stage. Fix the failure and rerun the
   entry point; do not skip a gate merely because another gate passed.

4. After validation, remove Firebase debug logs and restore only generated
   Flutter plugin registrant changes caused by the validation run. Do not
   discard intentional user changes.

5. Report:
   - the validated stage and branch
   - the pass/fail result for each gate
   - the absolute artifact directory printed by the script
   - the absolute path of every generated screenshot or other test artifact
   - any prerequisite that prevented a gate from running

## Browser prerequisites

Browser integration tests require the prerequisites documented by the selected
stage. For Stage 5 these include Chrome, a matching ChromeDriver on `PATH` or
in `CHROMEDRIVER_PATH`, Firebase CLI and Java, Windows Developer Mode, and free
local emulator ports.

Each invocation writes only its own browser artifacts under
`stageN/test-artifacts/stage-validation/<UTC timestamp>-<run ID>/`, so failure
reports cannot include screenshots left by an earlier run.
