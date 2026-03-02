# Mobile app tooling bootstrap (Windows)

This workspace includes a script that installs and maintains the Android + Flutter stack with pinned versions.

It also attempts to auto-accept Android SDK licenses and runs `flutter doctor -v` during `install`/`update`.

## What it installs

- Git
- Android Studio (includes Android SDK tooling)
- VS Code
- Node.js LTS
- Flutter SDK (installed from the official Flutter git repository, pinned by `tooling-config.json`)
- npm global: `firebase-tools`
- Dart global: `flutterfire_cli`
- VS Code extensions: Dart + Flutter

## Files generated

- `tooling-config.json` (desired versions; created on first run)
- `tooling-lock.json` (actual installed versions; updated after install/update)
- `tooling-versions.md` (human-readable version report)
- `logs/bootstrap-*.log` (full execution transcript)
- `logs/bootstrap-raw-*.log` (captured stdout/stderr from native commands, including npm/dart)

## Repository governance

- Project license: `LICENSE`
- Third-party notices: `THIRD_PARTY_NOTICES.md`
- Copilot repo instructions: `.github/copilot-instructions.md`
- App legal templates: `docs/legal/EULA.md` and `docs/legal/PRIVACY_POLICY.md`

This repository is currently maintained as proprietary source code (all rights reserved).

When dependency/tooling versions change, update license/notice docs in the same commit.

## Branch safety (no direct main commits)

This repo includes `.githooks/pre-commit` which blocks direct commits to `main`.

Enable hooks in your local clone:

```powershell
git config core.hooksPath .githooks
```

Recommended merge flow without PR:

```powershell
git checkout main
git merge --ff-only <topic-branch>
git push origin main
```

## Usage

Run PowerShell as **Administrator** in this folder.

Install pinned versions (uses `tooling-lock.json` if present, otherwise `tooling-config.json`):

```powershell
.\bootstrap-mobile-dev.ps1 -Command install
```

This command also runs Android license acceptance and a Flutter doctor check.

Update to latest available versions (then refresh lock file):

```powershell
.\bootstrap-mobile-dev.ps1 -Command update
```

Verify installed tooling:

```powershell
.\bootstrap-mobile-dev.ps1 -Command verify
```

Generate a fresh version report:

```powershell
.\bootstrap-mobile-dev.ps1 -Command report
```

## Android SDK prerequisites

If the script reports missing/incomplete Android SDK setup, complete this once in Android Studio:

> Important: the default Android Studio installation often does **not** install **Android SDK Command-line Tools** automatically.
> Also install the exact Android SDK Platform and Build-Tools versions requested by `flutter doctor -v`.
> In your current environment, Flutter Doctor is requesting Android SDK Platform **36**.

1. Open Android Studio.
2. Go to **Settings > Languages & Frameworks > Android SDK**.
3. In **SDK Platforms**, install the **Android SDK Platform version required by Flutter Doctor** (for example, API 36).
4. In **SDK Tools**, install:
	- Android SDK Platform-Tools
	- Android SDK Command-line Tools (latest)
	- Android SDK Build-Tools (the version required by Flutter Doctor)
	- If needed, enable **Show Package Details** to select/install specific versions.
5. Apply changes and close Android Studio.
6. Re-run:

```powershell
.\bootstrap-mobile-dev.ps1 -Command update
```

## Pinning behavior

- `install` = reproducible mode (prefers lock file, then config versions)
- `update` = upgrade mode (installs latest available, then rewrites lock file)

If you want to manually pin or change target versions, edit `tooling-config.json` and run `install`.

## Quick smoke-test loop

Use the helper script to run the Flutter smoke app with minimal setup each time:

```powershell
.\scripts\run-flutter-smoke.ps1
```

What it does:

- Checks if an Android emulator is already running.
- Starts an AVD only when none is running.
- Waits for emulator boot completion.
- Runs `flutter pub get` (unless skipped).
- Runs one of three modes:
	- `run`: `flutter run` on the emulator (default)
	- `build-run`: builds APK then installs + launches it
	- `install-run`: installs existing APK then launches it

Optional flags:

```powershell
.\scripts\run-flutter-smoke.ps1 -AvdName "Medium_Phone_API_36.1"
.\scripts\run-flutter-smoke.ps1 -SkipPubGet
.\scripts\run-flutter-smoke.ps1 -Mode build-run -BuildType debug
.\scripts\run-flutter-smoke.ps1 -Mode install-run -BuildType release
.\scripts\run-flutter-smoke.ps1 -BootTimeoutSeconds 420
```

### Mode guidance

- `run` (default): uses `flutter run` (build + install + launch + debug attach/hot reload).
- `build-run`: explicitly builds an APK, then installs and launches it.
- `install-run`: installs an already-built APK and launches it without running Flutter's full debug pipeline.

Why keep `install-run` if `flutter run` already installs?

- Faster launch when you already have a built APK.
- Useful for package/deployment sanity checks (especially `release` APK).
- Avoids debug attach/hot-reload when you only want install/launch behavior.

### Generated file churn (Windows line endings)

Flutter may touch generated registrant files during local runs. This repo keeps them tracked, with LF normalization in `.gitattributes`.

If these generated files show as modified but you did not intentionally change plugin dependencies, run:

```powershell
.\scripts\clean-flutter-generated.ps1
```
