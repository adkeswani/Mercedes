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

## Implementation style

- Keep changes focused and minimal.
- Avoid unrelated refactors.
- Prefer reproducible/pinned tooling versions.
