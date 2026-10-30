# Architecture

KDE Snap Overlay is a declarative KWin script (`X-Plasma-API: declarativescript`, main script `contents/ui/main.qml`) for Plasma 6 on Wayland. While a window is dragged to the top edge it shows a popup of Plasma's quick-tile layouts; dropping on a zone calls **KWin's own quick tiling**, so sticking and adjacent-resize behave exactly like KWin's edge tiling. The KWin internals it relies on, each verified in KWin's source, are in [kwin-notes.md](kwin-notes.md): read them before touching tiles, the drag/drop lifecycle, activation or screens.

## Repository map

| Path | What it is |
| --- | --- |
| `metadata.json` | KPackage metadata: `Id` `kde-snap-overlay`, `Version`, licence. |
| `contents/ui/main.qml` | Everything stateful (see below). |
| `contents/code/main.js` | Pure logic, `.pragma library`, imported as `Logic`: the `LAYOUTS` table and `ZONES` lookup, zone geometry and hit testing (`zoneRectFrac`, `zoneRectInPopup`, `hitTestZones`), KWin quick-tile identification (`quickZoneFor`, `quickTilesOf`), where the popup can hide (`revealPositions`) and config sanitising (`clampNumber`). No QML or KWin access, so it is unit-tested directly. |
| `contents/ui/components/` | `Selector.qml` (the card row), `Indicator.qml` (one card) and `ColorHelper.qml` (Kirigami colour tokens), forked from KZones 0.9.3 (see `NOTICE`). |
| `install.sh`, `package.sh` | Install/upgrade/uninstall and enable; build `kde-snap-overlay-<version>.kwinscript` (a zip of `metadata.json`, `contents/`, `LICENSE`, `NOTICE`). |
| `kde-snap-overlay-<version>.kwinscript` | The committed release package (only the current version). |
| `tests/` | Node unit suites (`*.test.mjs`) and `tests/kwin/`, multi-monitor scenarios against a real headless KWin ([README](../tests/kwin/README.md)). |
| `dev/` | Development tooling: `setup-container.sh` (the dev container) and `preview.sh` (install a preview build on the host). Never shipped. |
| `docs/` | This file and the KWin notes. |
| `assets/`, `screenshots/` | The logo and the README demo. |
| `.github/` | CI (`test.yml`: tests and linters), releases (`release.yml`) and issue/PR templates. |

## How `main.qml` is organised

`main.qml` is one `PlasmaCore.Dialog`, the popup, which owns a second full-screen, click-through `PlasmaCore.Dialog`, the zone overlay. Top to bottom:

1. **Window placement:** `x` and `y`. The reveal is a `Behavior` on `y` (see the contract).
2. **Configuration:** `readonly property` settings read with `KWin.readConfig` and sanitised by `Logic.clampNumber`, then the card metrics.
3. **State:** the drag screen (`screenArea`, `screenGeometry`, `otherScreens`, `dragScreen`), the reveal state (`fullZone`, `retracted`, `reveal`), the zone state (`highlightedZone`, `dwellCandidate`, `overlayZone`), the pending snap (`pendingZone`, `pendingWindow`, `pendingScreen`) and KWin's quick tiles (`quickTiles`, `hSplit`, `vSplit`).
4. **Functions** (all at 4-space indent, which the unit-test harness relies on):
   - startup and signal hookup: `startup`, `connectSignal`, `connectWindow`;
   - screens and desktops: `screenAt`, `screenForCursor`, `desktopFor`, `refreshScreenArea`, `retarget`, `onDesktopChanged`;
   - KWin's tiles: `findQuickTiles`, `zoneRect`, `tileEdge`;
   - the drag lifecycle: `onDragStarted`, `onTick` (the 16 ms cursor poll), `onDrop`, `onCommit`, `moveToScreen`, `onWindowRemoved`, `resetDrag`, `clearZoneState`, `clearPending`.
5. **Children:** the `Selector` card row, the overlay dialog and the timers (`pollTimer`, `commitTimer`, `dwellTimer`, `hideTimer`).

## Behaviour contract

These are deliberate; changing any of them is a behaviour change to agree on first.

- **Which drags:** only moves (not resizes) of windows KWin can tile, i.e. resizable ones; fixed-size and fullscreen windows get no popup.
- **Reveal:** the popup maps when the drag starts, directly at its hidden spot (no slide on the first map), hidden above the screen's real top edge (above any top panel), with room for its theme shadow, which KWin paints outside the window. Inside the trigger band (the top `activationDistance` px of the MaximizeArea, minus `edgeGapRatio` of the width on each side) it peeks a `peekHeight` sliver; within `showDistance` of the top, or while hovering the panel, it drops fully and rests `topGap` below the MaximizeArea top. Where another monitor sits directly above the popup's spot (a "shared" top edge, `Logic.revealPositions`), it hides above every monitor instead, skips the peek and appears without the slide, because KWin would draw those on that monitor.
- **Selection:** only over the card zones. Leaving the panel clears it, so a drop elsewhere never snaps. A 6 px leave margin absorbs hand tremor. The hit test uses the origin the Selector draws at (padding plus the theme-shadow compensation).
- **Overlay:** FancyZones' model. Cards highlight instantly; the full-screen overlay engages only after the cursor rests `highlightDelay` on one zone and fades in linearly over `overlayFadeIn`. Zone switches and hiding are instant. It is the script's own window because KWin hides its shared Outline on every motion step of a drag.
- **Geometry:** the overlay shows the target quick tile's exact `absoluteGeometry`, and the card diagrams use the live split lines (`hSplit`, `vSplit`). Both come from KWin's quick tiles for the drag screen and its desktop, reached through any quick-tiled window's `tile.parent`. With nothing quick-tiled there, KWin's grid is at its default 50/50, which is what the preview shows.
- **Drop:** the zone highlighted at release wins; the dwell gates only the visuals. A window that ends where it started never snaps (Escape puts it back; a press held until KWin starts the move may never move it). After 80 ms, `onCommit` activates the dropped window if needed (KWin's tile slots act on the active window, and a Meta+drag doesn't activate) and calls `Workspace.slotWindowQuickTile*`. It never tiles a different window. The snap lands on the monitor the popup was on: KWin tiles on the output under the window's centre, so a window whose centre is elsewhere is sent there first.
- **Drops KWin handles itself are left alone:** an Escape cancel (KWin restores the window, its position or its tile/maximize state, before announcing the finish), KWin's own edge tiling or maximize, and Shift-drop custom tiling.
- **Robustness:** crossing monitors or switching the drag screen's desktop mid-drag retargets the screen and its tiles; a watchdog ends a drag whose finish never arrives, without snapping; startup and every signal hookup are guarded (`connectSignal`); invalid config values fall back to their defaults.

## Known limitations

- Mouse drags only. X11 is untested; Plasma 5 isn't supported.
- Windows KWin can't tile (not resizable) get no popup.
- With no quick-tiled window on a screen, the script can't reach KWin's quick-tile root and assumes 50/50, which matches KWin's own state then.
- A Meta+drag snap activates the dropped window.
- Where a monitor sits directly above another, the lower one's popup has no peek stage and no slide.
