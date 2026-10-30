# Changelog

Notable changes to KDE Snap Overlay. Each release's GitHub notes are published from its section here.

## [Unreleased]

Multi-monitor and drag fixes, found and verified with a new real-KWin test bed.

**Fixes**
- **Wide windows on multiple monitors:** a window grabbed far from its centre could be previewed on one monitor and snapped onto another (KWin tiles on the monitor under the window's centre). It now always lands where the preview showed, on that monitor's desktop.
- **Monitors stacked vertically:** the hidden popup of the lower monitor showed along the bottom of the upper one during every drag. Where a monitor sits directly above, the popup now stays out of sight and appears without the peek stage and the slide.
- **Top panel:** part of the hidden popup showed over a top panel during every drag. The peek sliver now hangs off the screen's real top edge.
- **Shadow line:** the hidden popup's theme shadow left a faint line at the top centre of the screen during every drag (single monitor too).
- **Per-monitor desktops (Plasma 6.7):** switching the desktop on another monitor mid-drag no longer blinks the zone preview off, and each monitor's own desktop and tiles drive its preview.
- **First drag after login:** the popup no longer flashes onto the screen and slides away.
- **Escape:** a press held until KWin starts the move, then cancelled (or released) without moving, no longer snaps the window.
- **Fixed-size windows** (and fullscreen ones) no longer get a popup whose drop does nothing: KWin can't tile them.
- **`topGap` at its maximum:** the bottom of the cards is inside the trigger band again, so it snaps.

**Under the hood**
- `tests/kwin`: 23 scenarios run against a real, headless KWin with virtual monitors (stacked, offset, scaled, three monitors, a top panel, per-monitor desktops, hotplug mid-drag, Escape, first drag).
- One less handler on every window's geometry changes; the config unit test now checks `main.qml`'s own settings.
- The packages ship `LICENSE` and `NOTICE`; contributor docs moved to `CONTRIBUTING.md` and `docs/architecture.md`.

## [1.7.1] - 2026-09-28

Exact snap previews, multi-monitor support, and a hardened drop path.

**Snap preview — now exact**
- The fullscreen zone overlay and the card diagrams show KWin's own quick-tile geometry, read live from its tiles: the preview is exactly where the window will land, including resized splits and KWin re-balancing the grid mid-drag. Previously the tile tree was read through property names scripts cannot see, so any split not touched by a single tile fell back to 50/50.
- **Multi-monitor:** the popup, trigger band and preview follow the screen under the cursor during the drag, and the current virtual desktop if it switches mid-drag.

**Fixes**
- **Escape cancels:** cancelling the move while hovering a card no longer snaps the window. KWin's own edge tiling/maximize and Shift-drop tiling are never overridden either.
- **Meta+drag:** a window moved without being activated is now the one that snaps (KWin's tile slots act on the active window). If it can't be activated, nothing is tiled.
- Dropping off the cards no longer snaps to the last hovered zone — selection happens only over the cards.
- Hover areas line up with the drawn cards on themes with asymmetric dialog shadows.
- A second drop within 80 ms no longer commits early.
- `install.sh`: an upgrade is no longer misdetected as a fresh install, and the installer says when a re-login is needed.
- The package metadata now declares the correct licence (GPL-3.0-or-later).

**Hardening**
- A drag whose finish KWin never reports is ended by a watchdog instead of leaving the popup up.
- One misbehaving window at startup can no longer stop the script from following new windows; all signal hookups are guarded.
- Invalid config values fall back to their defaults instead of disabling the popup.

**Under the hood**
- Dead code removed (an unreachable native-geometry branch, unused helpers and properties); about 150 lines of tile-classifying heuristics replaced by two small, tested functions; the overlay rect is a plain binding instead of a 60 Hz recompute.
- `debugLog` also reports the grid source per drag/screen and any skipped snap.
- Plasma 6 only (the Plasma 5 install path could never load the script).

**Requirements:** Plasma / KWin 6 (tested on 6.7), Wayland.

Install via System Settings → Window Management → KWin Scripts → *Install from File…*, or clone and run `./install.sh` (log out and back in after an upgrade).
