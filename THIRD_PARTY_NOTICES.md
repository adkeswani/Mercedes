# Third-Party Notices

This repository uses and/or depends on third-party tools and packages with their own licenses.

## Current dependencies and tooling

- Flutter SDK (`flutter/flutter` GitHub repository) — BSD-3-Clause
- Dart SDK (bundled with Flutter) — BSD-3-Clause
- Android Studio + Android SDK tooling (`Google.AndroidStudio`) — multiple licenses by Google/JetBrains and Android component owners
- Node.js LTS (`OpenJS.NodeJS.LTS`) — mixed OSS licenses (primarily MIT-like/Node.js project licenses)
- Firebase CLI (`firebase-tools`) — MIT
- FlutterFire CLI (`flutterfire_cli`) — BSD-3-Clause
- Git (`Git.Git`) — GPL-2.0-only
- VS Code (`Microsoft.VisualStudioCode`) — Microsoft Software License Terms
- GitHub CLI (`GitHub.cli`) — MIT

### Flutter packages (stage2)

- `firebase_core` — BSD-3-Clause
- `firebase_auth` — BSD-3-Clause
- `google_sign_in` — BSD-3-Clause
- `cloud_firestore` — BSD-3-Clause
- `flutter_riverpod` — MIT
- `go_router` — BSD-3-Clause
- `url_launcher` — BSD-3-Clause
- `youtube_player_iframe` — BSD-3-Clause
- `flutter_lints` — BSD-3-Clause
- `fake_cloud_firestore` (dev) — BSD-3-Clause

### Node.js packages (functions/)

- `firebase-admin` — Apache-2.0
- `firebase-functions` — MIT
- `firebase-functions-test` (dev) — MIT
- `typescript` (dev) — Apache-2.0

## Source of truth

License terms are governed by each upstream project's official repository or installer terms.

## Maintenance policy

When adding, removing, or upgrading any dependency/tool in this repo:

1. Update this file to reflect the dependency and license.
2. Re-run `bootstrap-mobile-dev.ps1 -Command report`.
3. Commit updated `tooling-lock.json` and `tooling-versions.md` when versions change.
