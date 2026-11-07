# Apfelkiste

"Programs and Features" for the Mac: every app in one sortable list, with size, version, source and when you
last used it. Uninstall an app together with everything it leaves behind in `~/Library`.

- **List:** icon, name, version, size on disk with a bar relative to the biggest app, source (App Store,
  Homebrew, downloaded directly, Apple) and last activity. Sort by any column, search by name or bundle ID.
- **Crate header:** "110 Äpfel in der Kiste", space used, and the harvest bar: fresh, ripening and windfall
  apps as one segmented bar, plus a button that collects the windfall.
- **Last activity:** Spotlight's "last opened" is missing for many apps (login items, Setapp, helpers), so it
  is combined with Spotlight's usage days, the modification dates of the app's own files in `~/Library`
  (preferences, caches, web data, saved state, container) and whether it is running right now.
- **Own note:** accent color Apfelgrün (#2E7D32 light, #33853A dark) instead of system blue, tinted source
  icons in the sidebar, playful copy. Navigation and controls stay native.
- **Inspector:** "Was wirklich drinsteckt": app size plus leftovers, i.e. what uninstalling really frees.
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

`LeftoverFinder` only looks, it never deletes. It searches `~/Library`, `/Library`, launchd and installer receipts.

- **Sure matches** (preselected): `<folder>/<bundleID>` in both libraries and entries that start with
  `<bundleID>.` (helpers, `ByHost` preferences, privileged helpers). An entry is never claimed if a longer
  installed bundle ID matches it (`com.foo.app` never takes `com.foo.app.pro`).
- **Background services** (preselected): launch agents and daemons in `~/Library` and `/Library` that are
  named after the app, list it in `AssociatedBundleIdentifiers`, or run a program from inside its bundle.
  The privileged helper a daemon runs comes along. Services are stopped (`launchctl bootout`) before removal.
- **Installer receipts** (preselected): the `.pkg` that installed the app is found by checking third-party
  receipts for the bundle (`pkgutil --file-info` returns nothing for bundles on current macOS). Its receipt is
  forgotten (`pkgutil --forget`). Files it installed elsewhere are offered (at most 40, never system places).
- **Likely matches** (offered, not preselected): group containers with the app's team ID prefix (shared by all
  apps of that vendor), and folders named after the app in Application Support, Caches and Logs.
- Apps protected by SIP (Safari, apps that resolve into `/System`) are listed but can't be uninstalled.

## How removal works

`UninstallPlan` decides everything before anything is touched:

1. The app is asked to quit.
2. Items outside the home folder or owned by root (App Store apps, `/Library`, daemons, receipts) go into one
   shell script run with `do shell script … with administrator privileges`: one password prompt. It stops
   daemons, moves the items into the user's Trash (`mv`, with Finder-style names on collisions) and forgets
   receipts. Cancelling the prompt leaves everything untouched, because this step runs first.
3. Launch agents in the user's session are stopped.
4. Everything in the home folder goes to the Trash through Finder (`NSWorkspace.recycle`).

Nothing is deleted permanently. Items root moved into the Trash stay root-owned, as with Finder, so emptying
the Trash asks for the password again.

Not yet covered: leftovers of apps that are already gone, login items registered with `SMAppService`
(macOS cleans those up when the app disappears), system extensions.

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
