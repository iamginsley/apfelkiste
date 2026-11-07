# Apfelkiste

"Programs and Features" for the Mac: every app in one sortable list, with size, version, source and when you
last used it. Uninstall an app together with everything it leaves behind in `~/Library`.

- **List:** icon, name, version, size on disk, source (App Store, Homebrew, downloaded directly, Apple) and
  last use. Sort by any column, search by name or bundle ID, status bar with count and total size.
- **Fallobst (windfall):** the signature element. Every app gets a little apple: red when used in the last
  30 days, orange while it ripens, brown and fallen over once it hasn't been opened for 90 days (adjustable
  in the settings). The "Fallobst" sidebar entry collects these candidates for cleaning up.
- **Clean uninstall:** finds leftovers (Application Support, caches, preferences, containers, group
  containers, logs, saved state, web data, launch agents) and moves the app and the selected leftovers to
  the Trash. Nothing is deleted permanently. Running apps are asked to quit first. App Store apps owned by
  root trigger Finder's admin prompt.
- Homebrew casks are recognized; the uninstall sheet offers `brew uninstall --cask --zap` to copy.
- No backend, no account, no network. Nothing leaves the Mac.

## How leftovers are matched

`LeftoverFinder` only looks at `~/Library` and never deletes anything.

- **Bundle ID matches** (preselected): `<folder>/<bundleID>` and entries that start with `<bundleID>.`
  (helpers, `ByHost` preferences, launch agents). An entry is never claimed if a longer installed bundle ID
  matches it (`com.foo.app` never takes `com.foo.app.pro`).
- **Likely matches** (offered, not preselected): group containers with the app's team ID prefix (shared
  by all apps of that vendor), and folders named after the app in Application Support, Caches and Logs
  (only for names of at least five characters).
- Apps protected by SIP (Safari, apps that resolve into `/System`) are listed but can't be uninstalled.

Not yet covered: system-wide leftovers in `/Library` (need admin rights), login items and background
services, cleaning caches without uninstalling.

## Distribution

No App Sandbox, so no Mac App Store: the sandbox doesn't allow reading other apps' data or moving them
to the Trash. Distribution is Developer ID signed and notarized, see [docs/release.md](docs/release.md).

macOS asks once for "access data from other apps" when Apfelkiste looks into another app's container.
Leftovers in protected places are only found with that permission (or Full Disk Access).

## Project structure

```
Apfelkiste/
  App/                  App entry, menu commands, launch flags
  Core/Models/          InstalledApp, AppSource, Freshness, Leftover
  Core/Repositories/    AppRepository (live: LocalAppRepository)
  Core/Services/        AppScanner (bundles, Spotlight last use, signature team), DirectorySize,
                        HomebrewCasks, LeftoverFinder, Uninstaller (quit, Trash via Finder)
  Core/Demo/            Demo repository and icons for screenshots and tests (Debug only)
  Design/               Theme, FreshnessApple (signature element), AppIconView with cache
  Features/Apps/        Main window: sidebar, table, inspector, view model
  Features/Uninstall/   Uninstall sheet and view model
  Features/Settings/    Settings (windfall threshold)
ApfelkisteTests/        Unit tests (freshness, leftover matching, casks, sizes, view models),
                        snapshot render and an opt-in scan of the real Mac
scripts/                release.sh (DMG, notarization), make-icon.swift (renders the app icon)
docs/                   Privacy policy (German), release guide
```

## Run

```
cp Config.example.xcconfig Config.xcconfig
xcodegen generate
open Apfelkiste.xcodeproj
```

Debug launch flags: `-ApfelkisteDemo` (sample apps, nothing touches the disk),
`-ApfelkisteFilter windfall|appStore|homebrew|direct|apple`, `-ApfelkisteSelect <name>`,
`-ApfelkisteUninstall` (opens the uninstall sheet for the selected app).

Tests: `xcodebuild test -scheme Apfelkiste -destination 'platform=macOS'`.
Snapshots: `TEST_RUNNER_SNAPSHOT_DIR=/some/dir xcodebuild test … -only-testing:ApfelkisteTests/SnapshotRender`.
Scan this Mac: `TEST_RUNNER_REAL_SCAN=1 xcodebuild test … -only-testing:ApfelkisteTests/RealScanSmoke`.
