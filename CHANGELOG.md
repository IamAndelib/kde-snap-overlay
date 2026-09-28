# Changelog

Notable changes to KDE Snap Overlay. Each release's GitHub notes are published from its section here.

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
