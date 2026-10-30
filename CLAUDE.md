# KDE Snap Overlay: project memory

A KWin 6 script (KDE Plasma 6, Wayland) that shows a Windows-style "Snap Layouts" popup when a window is dragged to the top edge. Dropping on a zone applies **KWin's native quick tiling**, so sticking and adjacent-resize work exactly like KWin's own edge tiling. Author: IamAndelib. Licence: GPL-3.0-or-later (some components derive from KZones; see `NOTICE`).

**Status:** v1.7.1 is released and is the only GitHub release (all older releases and tags were deleted on purpose). `main` is the release branch.

## Repo map
- `metadata.json`: KPackage metadata (`Id` kde-snap-overlay, `Version`, licence). `X-Plasma-API: declarativescript`, main script `ui/main.qml`.
- `contents/ui/main.qml`: everything stateful. It's a `PlasmaCore.Dialog` popup that owns a second full-screen click-through `PlasmaCore.Dialog`, the zone overlay. It holds the 16 ms cursor poll (`onTick`), the drag lifecycle (`onDragStarted`, `onDrop`, `onCommit`, `onWindowRemoved`, `retarget`), and the reading of KWin's quick tiles (`findQuickTiles`, `zoneRect`, `tileEdge`).
- `contents/code/main.js`: pure logic, `.pragma library`. It holds the `LAYOUTS` table, a `ZONES` lookup, zone geometry/hit-testing, `quickZoneFor`/`quickTilesOf` (identify KWin's 8 quick tiles) and `clampNumber` (config sanitising). Keep it free of QML/KWin access so it stays unit-testable.
- `contents/ui/components/`: `Selector.qml` (card row), `Indicator.qml` (one card) and `ColorHelper.qml` (Kirigami colour tokens). All are forked from KZones 0.9.3.
- `install.sh`: install/upgrade/uninstall plus enable (Plasma 6 only). `package.sh` builds `kde-snap-overlay-<version>.kwinscript` (zip; needs `zip` and `jq`).
- `kde-snap-overlay-<version>.kwinscript`: the committed release artifact. Only the current version is kept.
- `tests/`: Node test suites (see Testing).
- `.github/workflows/`:
  - `test.yml` runs the tests on every push and PR;
  - `release.yml` runs on push to `main`: if `metadata.json`'s version has no GitHub release yet, it tests, builds, takes the notes from `CHANGELOG.md` and publishes it as Latest.
- `docs/kwin-notes.md`: the detailed KWin behaviour this script depends on, verified in KWin's source. **Read it before changing anything that touches tiles, the drag/drop lifecycle or activation.**

## Behaviour contract (don't change without asking)
- **Reveal:** the popup maps at grab time, retracted above the screen. Inside the trigger band (top `activationDistance` px, minus `edgeGapRatio` on each side) it peeks a sliver; within `showDistance` of the top, or while hovering the panel, it drops fully.
- **Selection:** only over the card zones. Leaving the panel clears it, so a drop elsewhere never snaps. A 6 px leave-margin hysteresis absorbs hand tremor. The hit test uses the same origin the Selector draws at (pad plus the theme-shadow compensation).
- **Overlay:** FancyZones' model. Cards highlight instantly; the full-screen overlay engages only after a `highlightDelay` dwell (150 ms) and fades in linearly over `overlayFadeIn` (200 ms). Zone switches and hiding are instant. The overlay is our own window because KWin's shared Outline is hidden on every motion step of a drag.
- **Geometry:** the overlay shows the target quick tile's exact `absoluteGeometry`, and the card diagrams use the live split lines (`hSplit`/`vSplit`). Both come from KWin's quick tiles, reached through any quick-tiled window's `tile.parent`. With nothing quick-tiled, the default 50/50 grid is used (which is KWin's own state in that case).
- **Drop:** the zone highlighted at release wins; the dwell gates only the visuals. After an 80 ms delay, `onCommit` activates the dropped window if needed and calls `Workspace.slotWindowQuickTile*`. It never tiles a different window.
- **Drops KWin handles itself are left alone:**
  - an Escape cancel (detected because KWin restores the window before emitting finished);
  - KWin's own edge tiling or maximize;
  - Shift-drop custom tiling.
- **Robustness:**
  - multi-monitor and desktop switches mid-drag re-target the screen and its tiles;
  - a watchdog ends a drag whose finish never arrives, without snapping;
  - startup and every signal hookup are guarded (`connectSignal`);
  - bad config values fall back to their defaults.

## KWin facts this code relies on (details and sources in docs/kwin-notes.md)
- `Window.quickTileGeometry()` is **not** scriptable. Read tiles instead.
- Scripts see the tile tree only through the Q_PROPERTYs `parent`, `tiles`, `relativeGeometry` and `absoluteGeometry`. The C++ names `parentTile`/`childTiles` are `undefined` in QML (this was the bug behind wrong previews before 1.7.1).
- The QuickRootTile has 8 children sharing **one** horizontal and **one** vertical split, clamped to [0.15, 0.85].
- `slotWindowQuickTile*` act on the **active** window, and Meta+drag doesn't activate.
- `interactiveMoveResizeFinished` also fires on **cancel**, after the restore.
- `requestedTileChanged` is synchronous; `tileChanged` waits for the client.

## Working rules (from development so far)
- Be meticulous and precise. **Never break working behaviour.** When a fix changes observable behaviour, ask first.
- Verify KWin behaviour in KWin's source (GitHub mirror: `https://raw.githubusercontent.com/KDE/kwin/<branch>/src/...`, for example `Plasma/6.6` or `master`) rather than guessing. Note the version the user runs.
- Plan non-trivial work first; ask before anything outward or irreversible (merging, releases, deleting releases/tags/branches, force-pushes).
- The user tests on a real Plasma session before any release. Hand them a test checklist.
- Every behaviour fix gets a test in `tests/lifecycle.test.mjs`. Prove it fails on the broken variant (mutation check below).
- Match the surrounding style: QML 4-space indent, comments that explain *why*, no new dependencies.
- Git: feature branch, then a PR, then a **merge commit** (not squash). Commit messages are conventional-ish (`fix:`, `feat:`, `chore:`) with an explanatory body.

## Testing and validation
- `node --test tests/*.test.mjs` (Node 22). 19 tests:
  - `quicktiles.test.mjs`: `quickZoneFor`/`quickTilesOf` against a replica of KWin's QuickRootTile;
  - `lifecycle.test.mjs`: extracts the real functions from `main.qml` and drives 14 scenarios against a fake KWin: drop, Escape cancel, Meta+drag, watchdog, multi-monitor, desktop switch, startup, config.
- The harness extracts functions declared at **4-space indent** in `main.qml` and fails loudly ("harness drift") if a listed function disappears. New popup-level state must also be declared in the harness scope.
- **Mutation check:** copy `contents/` to a temp folder, break the fix there, and run `KSO_ROOT=/tmp/copy node --test tests/lifecycle.test.mjs`. The guarding test must fail.
- **QML lint:** `python3 -m venv ~/.venvs/qt && ~/.venvs/qt/bin/pip install PySide6-Essentials`, then `~/.venvs/qt/bin/pyside6-qmllint contents/ui/main.qml`. KWin/Plasma modules are unavailable outside KWin, so import and "unqualified access" warnings are normal. Compare warning counts against `main` (no new warning *types*, no syntax errors).
- **Workflows:** `actionlint .github/workflows/*.yml` (for example via `pip install actionlint-py`).
- **Shell:** `bash -n install.sh package.sh`.

## Dev loop on the user's machine
- `./install.sh` installs or upgrades and enables the script; then **log out and back in**, because KWin can keep running a loaded script's old code.
- Debug: `kwriteconfig6 --file kwinrc --group Script-kde-snap-overlay --key debugLog true; qdbus6 org.kde.KWin /KWin reconfigure`, then `journalctl --user -f | grep kde-snap-overlay`. You'll see `grid h=… v=… source=quick-tiles|default screen=…` per drag and screen, overlay engage/switch/map lines, and skipped-snap notes.
- Config keys and ranges are in README "Configuration" (group `Script-kde-snap-overlay`).

## Release process
1. Bump `KPlugin.Version` in `metadata.json`. Keep the version line continuous (1.7.1, then 1.7.2 or 1.8.0).
2. Add `## [x.y.z] - YYYY-MM-DD` to `CHANGELOG.md`. Its body becomes the GitHub release notes. Follow the existing style: a headline, then **Fixes**, **Hardening**, **Under the hood**, **Requirements**, and an install line.
3. Run `./package.sh --force`, commit the new `.kwinscript`, `git rm` the previous one, and update the README's Option A file name.
4. Get the user's real-session sign-off, then merge to `main`. `release.yml` publishes the release (it refuses to publish if the CHANGELOG section is missing).
5. KDE Store uploads are manual (the user does them).

## Known limitations and ideas
- Mouse drags only. X11 is untested; Plasma 5 isn't supported.
- With no quick-tiled window on the screen, the script can't reach KWin's quick-tile root (it isn't exposed to scripts) and assumes 50/50. That matches KWin after `tryReset`.
- A Meta+drag snap gives the dropped window focus (needed because KWin's tile slots act on the active window).

## History, in brief
- Up to 1.7.0: the KZones-style popup, native dialog panel, FancyZones overlay model.
- 1.7.1:
  - cleanup (dead code removed, `.pragma library`, binding-based overlay rect);
  - the licence corrected from MIT to GPL-3.0-or-later;
  - exact KWin tile geometry (fixing the `parentTile`/`childTiles` bug);
  - fixes for Escape and Meta+drag;
  - hardening and multi-monitor support;
  - release automation.

  The old v2.x line was abandoned and removed.
- A sibling project, `window-geometry-restore`, lives in its own repo and is out of scope here.
