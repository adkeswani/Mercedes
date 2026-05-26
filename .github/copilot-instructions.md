# Copilot Instructions for this Repository

## Dependency and license governance

- Every dependency/tooling change must update licensing docs in the same change set.
- If a package or tool is added, removed, or version-pinned/updated, update:
  - `THIRD_PARTY_NOTICES.md`
  - `tooling-config.json` (if version intent changes)
  - `tooling-lock.json` and `tooling-versions.md` (after install/update/report)
- Do not merge dependency changes unless licensing notes are current.

## Branching and merge workflow

- Never commit directly on `main`.
- Use topic branches for all changes.
- Integrate topic branches into `main` using fast-forward merge only.
- No pull request is required for this solo-maintained repository.

## Stage-based directory convention

- Each implementation stage lives in its own directory (`stage1/`, `stage2/`, `stage3/`, …).
- When starting a new stage, copy the previous stage directory to a new one (e.g. `stage2/ → stage3/`).
- Rename the package (`name:` in `pubspec.yaml` and all `package:` imports) to match the new stage.
- Run `flutter pub get` and verify all existing tests pass before beginning new work.
- Previous stage directories are kept as-is for reference; all new development happens in the latest stage directory.

## Implementation style

- Keep changes focused and minimal.
- Avoid unrelated refactors.
- Prefer reproducible/pinned tooling versions.

## Testing

- Every code change must include unit tests for the new or modified behavior.
- If a change cannot be unit tested (e.g. pure UI wiring), document why in the commit message.

## Ownership and authorization

- All repository mutation methods (create, update, delete, publish) must verify ownership before writing.
- Use `verifyOwnership` or `_verifyOwnership` helpers that throw `StateError` on mismatch.
- Enrollment mutations must additionally verify the program is assignable and the caller is the program owner.
- These checks are defense-in-depth — Firestore security rules are the primary enforcement layer.
