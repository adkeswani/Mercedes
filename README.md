# Mobile app tooling bootstrap (Windows)

This workspace includes a script that installs and maintains the Android + Flutter stack with pinned versions.

It also attempts to auto-accept Android SDK licenses and runs `flutter doctor -v` during `install`/`update`.

## What it installs

- Git
- Android Studio (includes Android SDK tooling)
- VS Code
- Node.js LTS
- Flutter SDK
- npm global: `firebase-tools`
- Dart global: `flutterfire_cli`
- VS Code extensions: Dart + Flutter

## Files generated

- `tooling-config.json` (desired versions; created on first run)
- `tooling-lock.json` (actual installed versions; updated after install/update)
- `tooling-versions.md` (human-readable version report)
- `logs/bootstrap-*.log` (full execution transcript)

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

## Pinning behavior

- `install` = reproducible mode (prefers lock file, then config versions)
- `update` = upgrade mode (installs latest available, then rewrites lock file)

If you want to manually pin or change target versions, edit `tooling-config.json` and run `install`.
